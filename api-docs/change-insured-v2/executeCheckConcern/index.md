Hàm `executeCheckConcern` này chính là **application service layer** để gọi sang **external service (Check Concern API)** và chuyển đổi dữ liệu response về domain model nội bộ.

### 1. **Mục đích**

* Gửi request đến **Check Concern Service** (một hệ thống bên ngoài hoặc microservice khác).
* Nhận về danh sách **policyholder / insured** có cảnh báo (checklist liên quan đến cancel, block auto-acceptance…).
* Chuyển đổi response raw từ client → domain model `WarnedPerson`, `ExecuteCheckConcernResult`.

---

### 2. **Luồng xử lý**

1. **Call external API**

   ```kotlin
   val response = executeCheckConcernClient.invoke {
       executeCheckConcern(tenantIdGetter.getTenantId(), request.toApiRequest())
   }
   ```

    * Gọi client với `tenantId` và request đã map sang API request.
    * `invoke { ... }` có thể là wrapper để xử lý retry, logging, hoặc circuit breaker.

2. **Mapping Policyholder**

   ```kotlin
   val policyholder = response.policyholder?.let {
       WarnedPerson.Policyholder(
           policyholderId = PolicyholderId(it.personId),
           name = PersonName(it.name.full, it.name.katakana),
           dateOfBirth = it.dateOfBirth,
           infoCheckList = it.infoCheckList.map { checklist ->
               WarnedPerson.InfoCheckList(
                   concernChecklistId = ConcernChecklistId(checklist.concernCheckListId),
                   isCancelAlert = checklist.isCancelAlert,
                   isBlockAutoAcceptance = checklist.isBlockAutoAcceptance,
                   alertMessage = checklist.alertMessage,
               )
           },
       )
   }
   ```

    * Nếu response có policyholder thì convert sang domain object.
    * `infoCheckList` được map thành `WarnedPerson.InfoCheckList`.
    * Đảm bảo domain model luôn có type-safe id (`PolicyholderId`, `ConcernChecklistId`).

3. **Mapping Insureds (list)**

   ```kotlin
   val insureds = response.insureds?.map {
       WarnedPerson.Insured(
           insuredId = InsuredId(it.personId),
           name = PersonName(it.name.full, it.name.katakana),
           dateOfBirth = it.dateOfBirth,
           infoCheckList = it.infoCheckList.map { checklist ->
               WarnedPerson.InfoCheckList(
                   concernChecklistId = ConcernChecklistId(checklist.concernCheckListId),
                   isCancelAlert = checklist.isCancelAlert,
                   isBlockAutoAcceptance = checklist.isBlockAutoAcceptance,
                   alertMessage = checklist.alertMessage,
               )
           },
       )
   }
   ```

   → Tương tự như policyholder nhưng có thể nhiều insured.

4. **Build Result**

   ```kotlin
   return ExecuteCheckConcernResult(
       policyholder = policyholder,
       insureds = insureds.orEmpty(),
   )
   ```

    * Policyholder có thể `null`.
    * Insureds luôn trả về list (dùng `orEmpty()` để tránh null).

---

### 3. **Ý nghĩa business**

* `Check Concern` service có vẻ là **hệ thống kiểm tra blacklist / alert system** (ví dụ: khách hàng có tiền sử gian lận, bị chặn ký hợp đồng tự động…).

* Từ response, ta biết:

    * `isCancelAlert` → Có alert yêu cầu cancel không.
    * `isBlockAutoAcceptance` → Có chặn auto acceptance không.
    * `alertMessage` → Message hiển thị cho admin.

* Domain model `WarnedPerson` gom các cảnh báo này để các flow khác (ví dụ trong `changeInsured`) dùng để hiển thị hoặc xử lý rule.

## Code tham chiếu
```kotlin
override suspend fun executeCheckConcern(request: ExecuteCheckConcernRequest): ExecuteCheckConcernResult {
        val response = executeCheckConcernClient.invoke {
            executeCheckConcern(tenantIdGetter.getTenantId(), request.toApiRequest())
        }

        val policyholder = response.policyholder?.let {
            WarnedPerson.Policyholder(
                policyholderId = PolicyholderId(it.personId),
                name = PersonName(it.name.full, it.name.katakana),
                dateOfBirth = it.dateOfBirth,
                infoCheckList = it.infoCheckList.map { checklist ->
                    WarnedPerson.InfoCheckList(
                        concernChecklistId = ConcernChecklistId(checklist.concernCheckListId),
                        isCancelAlert = checklist.isCancelAlert,
                        isBlockAutoAcceptance = checklist.isBlockAutoAcceptance,
                        alertMessage = checklist.alertMessage,
                    )
                },
            )
        }
        val insureds = response.insureds?.map {
            WarnedPerson.Insured(
                insuredId = InsuredId(it.personId),
                name = PersonName(it.name.full, it.name.katakana),
                dateOfBirth = it.dateOfBirth,
                infoCheckList = it.infoCheckList.map { checklist ->
                    WarnedPerson.InfoCheckList(
                        concernChecklistId = ConcernChecklistId(checklist.concernCheckListId),
                        isCancelAlert = checklist.isCancelAlert,
                        isBlockAutoAcceptance = checklist.isBlockAutoAcceptance,
                        alertMessage = checklist.alertMessage,
                    )
                },
            )
        }

        return ExecuteCheckConcernResult(
            policyholder = policyholder,
            insureds = insureds.orEmpty(),
        )
    }
```