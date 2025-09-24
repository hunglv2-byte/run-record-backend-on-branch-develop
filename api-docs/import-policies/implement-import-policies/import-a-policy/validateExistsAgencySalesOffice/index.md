## Nghiệp vụ: Kiểm tra sự tồn tại của đại lý/văn phòng

### Input

* `agencyCode`: mã đại lý.
* `salesOfficeCode`: mã văn phòng (có thể null).

---

### Các bước xử lý

1. **Nếu không có `salesOfficeCode` (chỉ kiểm tra đại lý):**

    * Hệ thống kiểm tra trong cache (`agencyCache`) xem đại lý này đã được xác minh chưa.
    * Nếu chưa có trong cache → gọi `managementApiService.findAgencyByCode()` để xác nhận.
    * Nếu không tồn tại → ném lỗi `IllegalRecordException` với thông báo:

      > “Không tồn tại đại lý với mã {agencyCode}.”

2. **Nếu có `salesOfficeCode` (kiểm tra cặp đại lý + văn phòng):**

    * Hệ thống kiểm tra trong cache (`salesOfficeCache`) xem cặp `(agencyCode, salesOfficeCode)` đã được xác minh chưa.
    * Nếu chưa có trong cache → gọi `managementApiService.findSalesOfficeByCode()` để xác nhận.
    * Nếu không tồn tại → ném lỗi `IllegalRecordException` với thông báo:

      > “Không tồn tại văn phòng {salesOfficeCode} thuộc đại lý {agencyCode}.”

---

### ✅ Ý nghĩa nghiệp vụ

* Đảm bảo rằng **đại lý/văn phòng ghi trong dữ liệu import phải tồn tại trong hệ thống quản lý**.
* Nếu không tồn tại → chặn ngay, không cho phép import bản ghi đó.
* Có sử dụng **cache** để tránh gọi API quản lý quá nhiều lần, tăng hiệu năng.


## Code tham chiếu
```kotlin
suspend fun validateExistsAgencySalesOffice(agencyCode: AgencyCode, salesOfficeCode: SalesOfficeCode?) {
            if (salesOfficeCode == null) {
                val isAgencyValid = agencyCache.getOrPut(agencyCode) {
                    managementApiService.findAgencyByCode(agencyCode.value) != null
                }
                if (!isAgencyValid) {
                    throw IllegalRecordException(
                        ErrorMessages.illegalAgencySalesOffice(),
                        "代理店コード $agencyCode に紐づく代理店が存在しません。",
                    )
                }
            } else {
                val isSalesOfficeValid = salesOfficeCache.getOrPut(agencyCode to salesOfficeCode) {
                    managementApiService.findSalesOfficeByCode(agencyCode, salesOfficeCode) != null
                }
                if (!isSalesOfficeValid) {
                    throw IllegalRecordException(
                        ErrorMessages.illegalAgencySalesOffice(),
                        "代理店コード $agencyCode 営業所コード $salesOfficeCode の組み合わせが存在しません。",
                    )
                }
            }
        }
```