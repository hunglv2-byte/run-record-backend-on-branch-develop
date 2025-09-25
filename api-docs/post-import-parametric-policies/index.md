## API
```shell
curl --location 'http://localhost:8080/data-io-api/inputs/parametric-policies' \
--header 'Content-Type: application/json' \
--header 'Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImhJdlZwVWJ1SE9mOFNXUVFmdjRoUyJ9.eyJqb2luc3VyZV90ZW5hbnRfaWQiOiJtc2FkLWlucyIsImpvaW5zdXJlX2FnZW5jeV9jb2RlIjoiRFRLTCIsImpvaW5zdXJlX3NhbGVzX29mZmljZV9jb2RlIjoiTEtURCIsImpvaW5zdXJlX3VzZXJfaWQiOiI0MTRiYjkxNy01Y2I4LTRhMjQtYTYwNC1mNWUxMWJhYjhhNjAiLCJpc3MiOiJodHRwczovL2NvbnNvbGUtbG9naW4uZGV2LmpvaW5zdXJlLmpwLyIsInN1YiI6ImF1dGgwfDY4YTNlYjRlNzZjNjgyMzMxMTg2NTVjYSIsImF1ZCI6WyJodHRwczovL2FwaS1jb25zb2xlLmRldi5qb2luc3VyZS5qcCIsImh0dHBzOi8vam9pbnN1cmUtZGV2LWNvbnNvbGUuanAuYXV0aDAuY29tL3VzZXJpbmZvIl0sImlhdCI6MTc1ODI1MDk1OCwiZXhwIjoxNzU4MzM3MzU4LCJzY29wZSI6Im9wZW5pZCBwcm9maWxlIGVtYWlsIiwib3JnX2lkIjoib3JnX0Q5ZGtGQXYxcEFnQjg4SGEiLCJhenAiOiJvR0UxcWoyZGpabzVTdFRoZE5rQUJQazZTZGZxMUJLNyIsInBlcm1pc3Npb25zIjpbInJlYWQ6YWdlbmN5IiwicmVhZDpjbGFpbSIsInJlYWQ6ZGF0YS1pbyIsInJlYWQ6cGF5bWVudCIsInJlYWQ6cG9saWN5Iiwid3JpdGU6Y2xhaW0iLCJ3cml0ZTpkYXRhLWlvIiwid3JpdGU6cGF5bWVudCIsIndyaXRlOnBvbGljeSJdfQ.OVe2vFNXMlfD7_pGXRfvpbMwRyOwLbIj2KUv3VRe2oYGvhyNqbWKURys9ArlDA_WMaknSKrUXLFicro7Ijju5tbC3lihn2iBkrUtmnhaurqpZLxGFyvp7F3jodHZMp8mzGZuDhY1jZ60Ue-EdF72tISD21OOjqDX9aT_6VPFQFiAogVfAQ-CH6tNaLupdynTnJx-snxSx25mlxWFKmjuelSpwDdRld8wkef_I3PdDBJ5qC6aa2-qMicREYWB-XFxEedytFbpYhopTyxZbcNAfSVtkljgfC_eLnujQ2GAGYWCJxP4oSQvvGfL88Uh9gYrn-uw7o8t8XC2HC4o6r7k8w' \
--data '{
  "id": "e0fa52ff-19b8-40fb-ab60-7dc99e3f3b47",
  "file_name": "foo.csv"
}'
```

## Nghiệp vụ: Nhập khẩu hợp đồng bảo hiểm chỉ số (`import`)

### Input

* `command: ImportParametricPoliciesCommand`
  (bao gồm: `dataInputId`, `objectKey`, …)

### Các bước xử lý

1. **Khởi động import**

    * Log bắt đầu: `"import {dataInputId} process start"`.

2. **Tải dữ liệu mục tiêu (targets)**

    * Gọi `targetFileService.downloadParametricPolicyTargets(objectKey)` để lấy danh sách các bản ghi hợp đồng cần import.

3. **Chuẩn bị cache plan**

    * Vì có khả năng nhiều bản ghi cùng một `plan`, nên gọi `cachePlans(targets)` để load sẵn toàn bộ thông tin `plan` và lưu cache.

4. **Tạo bộ giới hạn song song (LimitedLauncher)**

    * Giới hạn số luồng xử lý song song theo cấu hình `IMPORT_PARALLELISM`.

5. **Xử lý từng bản ghi (`targets`) song song**

    * Với từng dòng (target):
      a. Nếu dòng này nằm trong chu kỳ log (`i % LOGGING_FREQUENCY == 0`), ghi log `"import {dataInputId} {i+1}/{size} import start"`.
      b. Gọi `importPolicy` để thực hiện import 1 hợp đồng:

        * **Kiểm tra liên kết với Doreca**

            * Tìm `contractPayeeAccount` theo `tel` và `dorecaRegistrationId`.
            * Nếu không tìm thấy → ghi log thất bại: `"dorecaとの紐づけができませんでした。"`
        * **Xác thực loại ví (walletType)**

            * Nếu `walletType` có giá trị nhưng không nằm trong danh sách hỗ trợ → ghi log thất bại: `"電子マネー種別が不正です。"`
        * **Chuẩn bị thông tin thanh toán bổ sung (`ParametricAdditionalPolicyPropertyDto`)**

            * Gồm: dorecaId, walletType, thông tin tài khoản ngân hàng (tên, mã ngân hàng, mã chi nhánh, số tài khoản, loại tài khoản).
        * **Tạo hợp đồng (`policyCommandService.createPolicy`)**

            * Truyền vào: param từ target, command, planDto, và propertyDto.
            * Ghi log start/end transaction nếu có `logFlag`.
        * Trả về `ImportLog` (thành công hoặc thất bại).

6. **Tổng hợp kết quả import**

    * Dùng `runCatching { it.await() }` để đợi toàn bộ tác vụ song song hoàn tất.
    * Nếu có lỗi bất ngờ, vẫn đợi tất cả hoàn thành rồi throw để catch.

7. **Upload kết quả**

    * Ghi log import (`importLogs`) lên file server (`fileManager.upload`).
    * Báo thành công cho `dataInputService.success` (cùng với số bản ghi thành công/skip).
    * Đăng ký log với `dataInputFileApiDriver.registerImportLog`.

8. **Xử lý ngoại lệ**

    * Nếu có lỗi:

        * Ghi log error `"契約一括インポートに失敗しました"`.
        * Báo fail cho `dataInputService.fail` với message phù hợp (từ `DisplayableException`, `DomainException`, hoặc fallback là `"予期せぬエラーが発生しました"`).
        * Re-throw lỗi để báo ngược ra ngoài.

9. **Kết thúc**

    * Ghi log `"import {dataInputId} process end"`.

---

### ✅ Ý nghĩa nghiệp vụ

* Đây là quy trình **import hợp đồng bảo hiểm chỉ số từ file**.
* Quy trình được tối ưu để:

    * Chạy **song song** nhiều bản ghi (có giới hạn).
    * Vẫn đảm bảo log đầy đủ cho việc theo dõi tiến độ.
    * Luôn **ghi lại kết quả import** (thành công, thất bại, skip).
    * Xử lý đầy đủ liên kết với hệ thống bên ngoài (Doreca, ví điện tử, ngân hàng).


### Code tham chiếu
```kotlin
suspend fun import(command: ImportParametricPoliciesCommand) {
        LOGGER.info("---- import ${command.dataInputId} process start")

        try {
            val targets = targetFileService.downloadParametricPolicyTargets(command.objectKey)

            // プランは重複している可能性があるので、先に取得しキャッシュとして扱う
            val planIdPlanDtoMap = cachePlans(targets)

            val limitedLauncher = getLimitedLauncher(IMPORT_PARALLELISM)

            val importLogs = targets.mapIndexed { i, rawTarget ->
                limitedLauncher.async {
                    // 各実行時間把握用のログ吐きは最低限にする
                    val logFlag = i % LOGGING_FREQUENCY == 0

                    if (logFlag) {
                        LOGGER.info("---- import ${command.dataInputId} ${ i + 1 }/${targets.size} import start")
                    }

                    importPolicy(command.dataInputId, rawTarget, planIdPlanDtoMap) { planDto, target ->
                        // doreca登録されているか
                        val contractPayeeAccount = findLatestByTelAndDorecaRegistrationId(
                            target.target.dorecaRegistrationId,
                            DorecaTel(target.target.tel.value),
                        ) ?: return@importPolicy ImportLog.failure(target.line, "dorecaとの紐づけができませんでした。")

                        val walletType = contractPayeeAccount.payeeEmoneyAccount?.walletTypeId?.value?.let { walletTypeIdValue ->
                            // walletTypeが指定されており、それが未対応だった場合はエラー
                            WalletType.entries.find { it.value == walletTypeIdValue }
                                ?: return@importPolicy ImportLog.failure(target.line, "電子マネー種別が不正です。")
                        }

                        val parametricAdditionalPolicyPropertyDto = ParametricAdditionalPolicyPropertyDto(
                            dorecaId = contractPayeeAccount.dorecaId,
                            walletType = walletType,
                            bankAccountName = contractPayeeAccount.payeeBankAccount?.bankAccountName,
                            bankCode = contractPayeeAccount.payeeBankAccount?.bankCode,
                            bankBranchCode = contractPayeeAccount.payeeBankAccount?.bankBranchCode,
                            bankAccountNumber = contractPayeeAccount.payeeBankAccount?.bankAccountNumber,
                            bankAccountType = contractPayeeAccount.payeeBankAccount?.bankAccountType,
                        )
                        if (logFlag) {
                            LOGGER.info("---- import ${command.dataInputId} ${ i + 1 }/${targets.size} import tran start")
                        }
                        policyCommandService.createPolicy(
                            param = target.target,
                            command = command,
                            planDto = planDto,
                            parametricAdditionalPolicyPropertyDto = parametricAdditionalPolicyPropertyDto,
                        )
                        if (logFlag) {
                            LOGGER.info("---- import ${command.dataInputId} ${ i + 1 }/${targets.size} import tran end")
                        }
                        target.toImportLog()
                    }
                }
            }
                // 途中で予期せぬエラーが起きていた場合も一旦全タスクを完了させた後にthrowしてcatch節へ
                .map { runCatching { it.await() } }
                .map { it.getOrThrow() }

            fileManager.upload(objectKeyFactory.createForImportLogs(command.dataInputId), importLogs)
            dataInputService.success(command.dataInputId, importLogs.completeCount(), importLogs.skipCount())
            dataInputFileApiDriver.registerImportLog(command.dataInputId)
        } catch (e: Exception) {
            LOGGER.error("${command.dataInputId}の契約一括インポートに失敗しました。", e)
            dataInputService.fail(
                command.dataInputId,
                when (e) {
                    is DisplayableException -> e.displayMessage
                    else -> (e as? DomainException)?.message ?: "予期せぬエラーが発生しました"
                },
            )
            throw e
        } finally {
            LOGGER.info("---- import ${command.dataInputId} process end")
        }
    }
```