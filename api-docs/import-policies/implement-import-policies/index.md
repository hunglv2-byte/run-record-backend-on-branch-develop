## Nghiệp vụ: Import hợp đồng bảo hiểm từ file dữ liệu

Hàm `import` nhận vào:

* `dataInputId` → ID của lần import
* `objectKey` → đường dẫn file dữ liệu gốc (trên storage)
* `scopes` → phạm vi người dùng thực hiện

---

### 1. Đọc dữ liệu từ file

```kotlin
val targets = targetFileService.downloadPolicyTargets(objectKey).toList()
```

* Hệ thống tải xuống file chứa danh sách hợp đồng bảo hiểm cần import.
* Biến `targets` là danh sách các dòng dữ liệu (mỗi dòng có thể **hợp lệ** hoặc **lỗi parse**).

---

### 2. Chuẩn bị môi trường xử lý

```kotlin
val now = currentDateTime()
val cache = ApiCache()
```

* Ghi lại thời điểm hiện tại (`now`) để đồng bộ dữ liệu.
* Tạo một cache (`ApiCache`) để tái sử dụng thông tin trong suốt quá trình import (giảm số lần gọi API).

---

### 3. Xử lý từng dòng dữ liệu trong file

```kotlin
val importLogs = targets.map { ... }
```

* Với mỗi dòng (`target`):

  **Trường hợp dữ liệu hợp lệ (`ImportTarget.Success`):**

    * Gọi `importPolicy` để đăng ký hợp đồng vào hệ thống:
      * [Import 1 hợp đồng bảo hiểm (Policy)](import-a-policy/index.md)
    * Nếu thành công → ghi log thành công.
    * Nếu thất bại:

        * **DisplayableException** (lỗi nghiệp vụ, có thể hiển thị cho người dùng):

            * Ghi log lỗi với lý do cụ thể.
            * Tiếp tục xử lý các dòng khác.
        * **Exception** (lỗi không lường trước):

            * Gửi cảnh báo tới hệ thống giám sát (`systemAlerter`).
            * Ghi log lỗi chung: "Đã xảy ra lỗi không lường trước khi đăng ký".
            * Tiếp tục xử lý các dòng khác.

  **Trường hợp dữ liệu lỗi ngay từ đầu (`ImportTarget.Failure`):**

    * Chuyển trực tiếp thành log lỗi, không xử lý tiếp.

---

### 4. Lưu log kết quả import

```kotlin
fileManager.upload(objectKeyFactory.createForImportLogs(dataInputId), importLogs)
```

* Upload file log chứa kết quả import (thành công/thất bại của từng dòng).

---

### 5. Cập nhật trạng thái import

```kotlin
dataInputService.success(dataInputId, importLogs.completeCount(), importLogs.skipCount())
dataInputFileApiDriver.registerImportLog(dataInputId)
```

* Đánh dấu lần import này **thành công**.
* Ghi nhận số lượng dòng thành công và số lượng dòng bị bỏ qua.
* Đăng ký file log vào hệ thống quản lý file.

---

### 6. Xử lý lỗi ở cấp độ toàn bộ file

* Nếu xảy ra **DisplayableException** trong toàn bộ tiến trình:

    * Đánh dấu import thất bại với lý do cụ thể.
    * Ném lỗi ra ngoài.

* Nếu xảy ra **Exception** không lường trước:

    * Gửi cảnh báo tới hệ thống giám sát.
    * Đánh dấu import thất bại với thông báo chung: "Đã xảy ra lỗi không lường trước".
    * Ném lỗi ra ngoài.

---

## ✅ Tóm tắt luồng nghiệp vụ

1. Tải file dữ liệu cần import.
2. Lặp qua từng dòng:

    * Thành công → đăng ký hợp đồng.
    * Thất bại → ghi log lỗi, nhưng **không dừng toàn bộ import**.
3. Sau khi xử lý hết:

    * Lưu lại file log kết quả.
    * Cập nhật trạng thái import (thành công/thất bại).
4. Nếu gặp lỗi nghiêm trọng toàn file → dừng và báo lỗi.

### Code tham chiếu
```kotlin
suspend fun import(dataInputId: DataInputId, objectKey: String, scopes: ReferenceScopes.ConsoleUser) {
        try {
            val targets = targetFileService.downloadPolicyTargets(objectKey).toList()

            val now = currentDateTime()
            val cache = ApiCache()

            val importLogs = targets.map {
                when (it) {
                    is ImportTarget.Success -> {
                        try {
                            importPolicy(scopes, it.target, now, cache)

                            it.toImportLog()
                        } catch (e: DisplayableException) {
                            // DisplayableExceptionが発生した場合は、エラー理由を記録して処理を継続する
                            LOGGER.warn(e.message, e)
                            ImportLog.failure(it.line, e.displayMessage)
                        } catch (e: Exception) {
                            // 予期せぬエラーが発生した場合はアラートを出して処理を続ける
                            systemAlerter.low("${dataInputId}の契約登録中に予期せぬエラーが発生しました。", e)
                            ImportLog.failure(it.line, "登録処理中に予期せぬエラーが発生しました。")
                        }
                    }

                    is ImportTarget.Failure -> it.toImportLog()
                }
            }

            fileManager.upload(objectKeyFactory.createForImportLogs(dataInputId), importLogs)
            dataInputService.success(dataInputId, importLogs.completeCount(), importLogs.skipCount())
            dataInputFileApiDriver.registerImportLog(dataInputId)
        } catch (e: DisplayableException) {
            dataInputService.fail(dataInputId, e.displayMessage)
            throw e
        } catch (e: Exception) {
            systemAlerter.low("${dataInputId}の契約一括インポートに失敗しました。", e)
            dataInputService.fail(dataInputId, "予期せぬエラーが発生しました")
            throw e
        }
    }
```