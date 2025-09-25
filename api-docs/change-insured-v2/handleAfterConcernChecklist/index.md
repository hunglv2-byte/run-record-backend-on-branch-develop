Hàm `handleAfterConcernChecklist` này chính là **post-processing** sau khi gọi `executeCheckConcern` để cập nhật lại **concern alerts** (cảnh báo liên quan đến Insured) trong DB.

### 1. **Mục đích**

* Quản lý vòng đời của **concern alerts** (cảnh báo liên quan đến khách hàng được bảo hiểm).
* Khi thông tin insured thay đổi (ví dụ sau `changeInsured`), ta cần:

    1. **Đóng hiệu lực** các alert cũ.
    2. **Thêm alert mới** từ kết quả check concern (nếu có).
    3. **Loại bỏ (cancel)** các alert có thể hủy ngay.

---

### 2. **Luồng xử lý**

#### (a) Lấy danh sách alert cũ và đóng hiệu lực

```kotlin
val oldConcernAlerts = concernAlertService.findInsuredConcernAlertsByInsuredId(newResult.id).toList()
val updateAlerts = oldConcernAlerts
    .filter { it.endAt == null || it.endAt?.toInstant() == INFINITE_DATETIME.toInstant() }
    .map { it.updateValidDateTime(it.startAt, newResult.validFrom) }
```

* Lấy tất cả alert đang gắn với insured.
* Chỉ chọn những alert **chưa có ngày kết thúc** hoặc **endAt = ∞** (đang hiệu lực).
* Đóng hiệu lực của chúng bằng cách set `endAt = newResult.validFrom` (tức kết thúc ngay trước khi insured mới bắt đầu hiệu lực).

→ Mục đích: đảm bảo alert cũ không còn áp dụng cho insured sau thay đổi.

---

#### (b) Lưu update vào DB

```kotlin
if (updateAlerts.isNotEmpty()) {
    concernAlertService.saveInsuredAlerts(updateAlerts)
}
```

* Chỉ save khi có thay đổi thực sự.

---

#### (c) Thêm alert mới từ danh sách `insureds` (nếu có)

```kotlin
if (!insureds.isNullOrEmpty()) {
    val infoChecklists = insureds.flatMap { it.infoCheckList }
    concernAlertService.saveInsuredAlerts(
        infoChecklists.map { infoChecklist ->
            ConcernAlertAggregate.Insured.create(
                insuredId = newResult.id,
                policyId = newResult.policyId,
                concernChecklistId = infoChecklist.concernChecklistId,
                isCancelAlert = infoChecklist.isCancelAlert,
                isBlockAutoAcceptance = infoChecklist.isBlockAutoAcceptance,
                alertMessage = infoChecklist.alertMessage,
                startAt = newResult.validFrom,
                endAt = newResult.validTo,
            ).run {
                // 契約異動では、解除できるアラートは即時解除する, 解除できないもののみアラート表示する
                if (isCancelAlert) cancel() else this
            }
        },
    )
}
```

* Với mỗi `InfoCheckList` (cảnh báo mới từ service bên ngoài), tạo một alert mới gắn vào insured (`ConcernAlertAggregate.Insured`).
* Thời gian hiệu lực chính là `[validFrom, validTo]` của insured mới.
* Nếu alert có `isCancelAlert = true` → cancel ngay lập tức (không để hiển thị).
* Ngược lại, giữ lại để hệ thống hiển thị cảnh báo.

---

### 3. **Ý nghĩa nghiệp vụ**

* Hệ thống muốn **đồng bộ concern alert với trạng thái insured mới nhất**.
* Cơ chế:

    * Alert cũ được đóng hiệu lực → tránh mâu thuẫn.
    * Alert mới được thêm vào theo kết quả mới nhất từ service bên ngoài.
    * Những alert “có thể hủy” thì hủy ngay, còn “không thể hủy” thì hiển thị để người dùng xử lý.

---

### 4. **Điểm quan trọng**

* **BiTemporal**: có `startAt`, `endAt` để quản lý hiệu lực theo thời gian.
* **Idempotent logic**: alert cũ bị đóng lại trước khi thêm alert mới, tránh alert trùng lặp.
* **Rule đặc biệt**: chỉ giữ lại những cảnh báo không thể hủy (`isCancelAlert == false`).

### Code tham chiếu

```kotlin
private suspend fun handleAfterConcernChecklist(insureds: List<WarnedPerson>?, newResult: InsuredAggregate) {
        // 既存のconcert alertsの有効日時を更新する
        val oldConcernAlerts = concernAlertService.findInsuredConcernAlertsByInsuredId(newResult.id).toList()
        val updateAlerts = oldConcernAlerts
            .filter { it.endAt == null || it.endAt?.toInstant() == INFINITE_DATETIME.toInstant() }
            .map { it.updateValidDateTime(it.startAt, newResult.validFrom) }

        if (updateAlerts.isNotEmpty()) {
            concernAlertService.saveInsuredAlerts(updateAlerts)
        }

        if (!insureds.isNullOrEmpty()) {
            val infoChecklists = insureds.flatMap { it.infoCheckList }
            // 削除できないconcern alertsのみをDBに追加する
            concernAlertService.saveInsuredAlerts(
                infoChecklists.map { infoChecklist ->
                    ConcernAlertAggregate.Insured.create(
                        insuredId = newResult.id,
                        policyId = newResult.policyId,
                        concernChecklistId = infoChecklist.concernChecklistId,
                        isCancelAlert = infoChecklist.isCancelAlert,
                        isBlockAutoAcceptance = infoChecklist.isBlockAutoAcceptance,
                        alertMessage = infoChecklist.alertMessage,
                        startAt = newResult.validFrom,
                        endAt = newResult.validTo,
                    ).run {
                        // 契約異動では、解除できるアラートは即時解除する, 解除できないもののみアラート表示する
                        if (isCancelAlert) cancel() else this
                    }
                },
            )
        }
    }
```