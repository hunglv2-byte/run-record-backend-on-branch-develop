## API
```shell
curl --location 'http://localhost:8080/data-io-api/inputs/policies' \
--header 'Content-Type: application/json' \
--header 'Authorization: Bearer eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCIsImtpZCI6ImhJdlZwVWJ1SE9mOFNXUVFmdjRoUyJ9.eyJqb2luc3VyZV90ZW5hbnRfaWQiOiJtc2FkLWlucyIsImpvaW5zdXJlX2FnZW5jeV9jb2RlIjoiRFRLTCIsImpvaW5zdXJlX3NhbGVzX29mZmljZV9jb2RlIjoiTEtURCIsImpvaW5zdXJlX3VzZXJfaWQiOiI0MTRiYjkxNy01Y2I4LTRhMjQtYTYwNC1mNWUxMWJhYjhhNjAiLCJpc3MiOiJodHRwczovL2NvbnNvbGUtbG9naW4uZGV2LmpvaW5zdXJlLmpwLyIsInN1YiI6ImF1dGgwfDY4YTNlYjRlNzZjNjgyMzMxMTg2NTVjYSIsImF1ZCI6WyJodHRwczovL2FwaS1jb25zb2xlLmRldi5qb2luc3VyZS5qcCIsImh0dHBzOi8vam9pbnN1cmUtZGV2LWNvbnNvbGUuanAuYXV0aDAuY29tL3VzZXJpbmZvIl0sImlhdCI6MTc1ODI1MDk1OCwiZXhwIjoxNzU4MzM3MzU4LCJzY29wZSI6Im9wZW5pZCBwcm9maWxlIGVtYWlsIiwib3JnX2lkIjoib3JnX0Q5ZGtGQXYxcEFnQjg4SGEiLCJhenAiOiJvR0UxcWoyZGpabzVTdFRoZE5rQUJQazZTZGZxMUJLNyIsInBlcm1pc3Npb25zIjpbInJlYWQ6YWdlbmN5IiwicmVhZDpjbGFpbSIsInJlYWQ6ZGF0YS1pbyIsInJlYWQ6cGF5bWVudCIsInJlYWQ6cG9saWN5Iiwid3JpdGU6Y2xhaW0iLCJ3cml0ZTpkYXRhLWlvIiwid3JpdGU6cGF5bWVudCIsIndyaXRlOnBvbGljeSJdfQ.OVe2vFNXMlfD7_pGXRfvpbMwRyOwLbIj2KUv3VRe2oYGvhyNqbWKURys9ArlDA_WMaknSKrUXLFicro7Ijju5tbC3lihn2iBkrUtmnhaurqpZLxGFyvp7F3jodHZMp8mzGZuDhY1jZ60Ue-EdF72tISD21OOjqDX9aT_6VPFQFiAogVfAQ-CH6tNaLupdynTnJx-snxSx25mlxWFKmjuelSpwDdRld8wkef_I3PdDBJ5qC6aa2-qMicREYWB-XFxEedytFbpYhopTyxZbcNAfSVtkljgfC_eLnujQ2GAGYWCJxP4oSQvvGfL88Uh9gYrn-uw7o8t8XC2HC4o6r7k8w' \
--data '{
  "id": "e0fa52ff-19b8-40fb-ab60-7dc99e3f3b47",
  "file_name": "foo.csv"
}'
```

## Luồng nghiệp vụ
1. **Xác định quyền của người dùng**
    * Hệ thống kiểm tra thông tin của người dùng thực hiện import:
      * [Lấy phạm vi tham chiếu (Reference Scopes) của User](get-reference-scopes-user/index.md)
    * Lấy ra mã đại lý (**agencyCode**) và mã văn phòng (**salesOfficeCode**) mà người đó thuộc về.
2. **Khởi tạo yêu cầu import**
    * Hệ thống tạo một bản ghi mô tả yêu cầu import:
        * ID của lần import.
        * Loại import (tạo mới).
        * Tên file và định dạng file mà người dùng đã tải lên.
        * Loại dữ liệu cần import là **hợp đồng bảo hiểm**.
        * Thông tin người dùng, đại lý, văn phòng.
3. **Ghi nhận vào hệ thống**
    * Lưu thông tin yêu cầu import này vào cơ sở dữ liệu để quản lý và theo dõi.
4. **Chuẩn bị truy cập file dữ liệu**
    * Tạo đường dẫn (object key) để trỏ đến file dữ liệu gốc đã được tải lên hệ thống lưu trữ.
5. **Thực hiện import**
    * Hệ thống chạy tiến trình import ở chế độ nền (background).
    * Tiến trình này gọi đến dịch vụ import chính (Policy Import API) để:
        * [Import hợp đồng bảo hiểm từ file dữ liệu](implement-import-policies/index.md)


### Code tham chiếu
```kotlin
suspend fun importPolicies(
        dataInputId: DataInputId,
        fileName: String,
        inputFormat: InputFormat,
        userId: UserId,
    ) {
        val referenceScopes = managementApiDriver.getUserReferenceScopesByUserId(userId)
        val (agencyCode, salesOfficeCode) = referenceScopes.getAgencyAndSalesOffice()

        val aggregate = DataInputAggregate.create(
            dataInputId = dataInputId,
            inputType = InputType.CREATE,
            inputFileName = fileName,
            inputFormat = inputFormat,
            inputTarget = POLICIES,
            userId = userId,
            agencyCode = agencyCode,
            salesOfficeCode = salesOfficeCode,
        )

        val result = dataInputRepository.save(aggregate)
        val objectKey = dataInputObjectKeyFactory.reconstruct(
            dataInputId = result.id,
            extension = FileExtension.fromFileName(result.inputFileName),
        )

        launchImport(result, objectKey) { aggregate, objectKey ->
            policyImportsApiDriver.importPolicies(aggregate.id, objectKey, aggregate.userId, referenceScopes)
        }
    }
```

## References
- [Import Policies](https://docs.google.com/document/d/1HAKe3u1v_YAEbZweR6Xxp_BEFIdhu6herMJLv3kNmfo/edit?tab=t.0)