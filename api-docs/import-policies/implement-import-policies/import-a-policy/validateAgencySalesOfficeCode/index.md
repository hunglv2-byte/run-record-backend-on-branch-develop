## Nghiệp vụ: Xác minh đại lý và văn phòng giao dịch của bản ghi hợp đồng

### Input:

* `referenceScopes`: phạm vi tham chiếu (quyền hạn) của người dùng console.
* `agencyCode`: mã đại lý có trong dữ liệu hợp đồng.
* `salesOfficeCode`: mã văn phòng giao dịch (nếu có).

---

### Các bước xử lý:

1. **Kiểm tra quyền truy cập:**

    * Hệ thống so sánh `agencyCode` và `salesOfficeCode` của bản ghi với phạm vi mà user hiện tại có quyền tham chiếu (`referenceScopes`).

2. **Nếu hợp lệ:**

    * Không làm gì thêm, tiếp tục các bước import khác.

3. **Nếu không hợp lệ:**

    * Hệ thống ném ra `IllegalRecordException` với thông tin chi tiết:

        * Thông báo lỗi nghiệp vụ (`ErrorMessages.illegalAgencySalesOffice()`).
        * Thông tin cụ thể: quyền hạn user, mã đại lý, mã văn phòng bị từ chối.

---

## ✅ Ý nghĩa nghiệp vụ

Hàm này đảm bảo rằng **người dùng chỉ được phép import hợp đồng của những đại lý/văn phòng nằm trong phạm vi mà họ được cấp quyền**.

* Nếu user cố import dữ liệu ngoài phạm vi, hệ thống sẽ **chặn ngay từ đầu** và báo lỗi.

## Code tham chiếu

```kotlin
suspend fun validateAgencySalesOfficeCode(
        referenceScopes: ReferenceScopes.ConsoleUser,
        agencyCode: AgencyCode,
        salesOfficeCode: SalesOfficeCode?,
    ) {
        if (!referenceScopes.isReferable(agencyCode, salesOfficeCode)) {
            throw IllegalRecordException(
                ErrorMessages.illegalAgencySalesOffice(),
                "参照不可能な代理店・営業所が指定されました 権限: $referenceScopes 代理店: $agencyCode 営業所 $salesOfficeCode",
            )
        }
    }
```