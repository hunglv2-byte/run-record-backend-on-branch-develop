## API
```shell
PUT http://localhost:8080/v2/policies/{policy_id}/insureds/{insured_id}/change
Content-Type: application/json
{
  "insured": {
    "consumer": {
      "object_type": "NATURAL_PERSON",
      "name_full": "山田太郎",
      "name_katakana": "ヤマダタロウ",
      "date_of_birth": "1966-06-06",
      "sex": "1"
    },
    "additional_policy_properties": [
      {
        "name": "BMI",
        "value": "25"
      }
    ]
  },
  "updated_at": "2022-04-05T00:00:00+09:00",
  "remarks": "CHANGED",
  "force-save-if-check-limit-fails": false
}
```

## 📌 Mục đích

Hàm này xử lý việc **thay đổi thông tin Người được bảo hiểm (Insured)** trong một hợp đồng.
Các thay đổi có thể bao gồm:

* Cập nhật thông tin cá nhân (ConsumerPatch).
* Cập nhật thông tin bổ sung trong hợp đồng (AdditionalPolicyProperties).
* Ghi nhận remark, userId, và thời điểm thay đổi.

---

## 📌 Flow xử lý chi tiết

1. **Xác định thời gian hiện tại & lấy hợp đồng**

   ```kotlin
   val currentDateTime = currentDateTime()
   val policy = policyCommandService.getPolicyBy(command.policyId, command.userId, currentDateTime)
   ```

   → Lấy thông tin hợp đồng theo policyId + userId tại thời điểm hiện tại.

---

2. **Lấy thông tin Insured mới nhất**

   ```kotlin
   val latestInsured = insuredService.findLatestInsured(command.insuredId).validate(command.policyId)
   ```

   → Tìm người được bảo hiểm mới nhất (có thể bao gồm cả các thay đổi dự kiến trong tương lai).
   → Kiểm tra Insured có thuộc hợp đồng hiện tại không.

---

3. **Validate thông tin thanh toán liên quan đến Insured**

   ```kotlin
   validateInsuredPaymentInfo(
       originAdditionalProperties = latestInsured.additionalPolicyProperties,
       inputAdditionalProperties = command.additionalPolicyProperties,
   )
   ```
    
   → Kiểm tra tính hợp lệ của thông tin thanh toán khi có thay đổi.
   (hiện tại áp dụng riêng cho **MSAD-INS**, nhưng vẫn viết dạng array để hỗ trợ tenant khác trong tương lai).
    * [Xem chi tiết hàm validateInsuredPaymentInfo](validateInsuredPaymentInfo/index.md)
---

4. **Thay đổi Insured (áp dụng patch)**

   ```kotlin
   val newInsured = latestInsured.change(
       currentPolicyStatus = policy.policyStatus,
       issuedAt = policy.issuedAt,
       inputConsumerPatch = command.consumerPatch,
       inputAdditionalPolicyProperties = command.additionalPolicyProperties,
       changedAt = command.changedAt,
       remarks = command.remarks,
       userId = command.userId,
   )
   ```

   → Tạo một đối tượng Insured mới từ Insured hiện tại + thông tin thay đổi (`consumerPatch`, `additionalPolicyProperties`).

---

5. **Lưu thay đổi Insured**

   ```kotlin
   val changeResult = insuredService.changeInsured(newInsured)
   ```

---

6. **Nếu Insured là cá nhân → Thực hiện kiểm tra danh sách cảnh báo (Concern checklist)**

   ```kotlin
   (changeResult.consumer.takeIf { it.isNaturalPerson() }?.asNaturalPerson())?.let { consumer ->
       command.toExecuteCheckConcernRequest(...)? .also { request ->
           val insuredAfterChanged = insuredService.findLatestInsured(command.insuredId).validate(command.policyId)
           val warnedPersons = executeCheckConcernApiService.executeCheckConcern(request)
           val insureds = warnedPersons.insureds
           handleAfterConcernChecklist(insureds, insuredAfterChanged)
       }
   }
   ```

   → Nếu người được bảo hiểm là **cá nhân** thì:

    * Gửi request sang hệ thống kiểm tra cảnh báo (check concern API).
      * [Xem chi tiết hàm executeCheckConcern](executeCheckConcern/index.md)
    * Lấy danh sách cảnh báo trả về.
    * Xử lý kết quả cảnh báo trên Insured vừa được thay đổi.
      * [Xem chi tiết hàm handleAfterConcernChecklist](handleAfterConcernChecklist/index.md)

---

7. **Kiểm tra hạn mức bảo hiểm (Limit check)**

   ```kotlin
   checkLimitIfNeeded(
       patch = command.consumerPatch,
       forceSaveIfCheckLimitFails = command.forceSaveIfCheckLimitFails,
       policy = policy,
       editAt = command.changedAt,
       now = currentDateTime,
       editedConsumer = newInsured.consumer,
   )
   ```

   → Sau khi thay đổi Insured, kiểm tra xem thông tin mới có vượt quá hạn mức bảo hiểm hay không.

    * Nếu vượt, có thể cho phép ghi đè (forceSave) nếu command cho phép.

---

8. **Trả về kết quả**

   ```kotlin
   return V2InsuredChangeCommandResult(changeResult)
   ```

---

## 📌 Ý nghĩa nghiệp vụ

* Cho phép **cập nhật thông tin Người được bảo hiểm (Insured)** trong hợp đồng bảo hiểm.
* Đảm bảo:

    * ✅ Hợp đồng hợp lệ tại thời điểm thay đổi.
    * ✅ Người được bảo hiểm thuộc về hợp đồng đó.
    * ✅ Thông tin thanh toán đúng format.
    * ✅ Kiểm tra blacklist / watchlist (Concern check).
    * ✅ Không vi phạm hạn mức bảo hiểm.
* Ghi nhận toàn bộ thay đổi cùng **remarks, thời gian, userId** để phục vụ audit.

## Code tham chiếu
```kotlin
suspend fun changeInsured(command: V2InsuredChangeCommand): V2InsuredChangeCommandResult {
        // TODO: 契約は現在日時、被保険者は予約含む最新から反映している。BiTemporal的な不整合が想定されるため複雑な変更ケースでバグるかも
        val currentDateTime = currentDateTime()
        val policy = policyCommandService.getPolicyBy(command.policyId, command.userId, currentDateTime)
        val latestInsured = insuredService.findLatestInsured(command.insuredId).validate(command.policyId)

        // TODO MSAD-INSのみの仕様だが、デモテナント等を考慮して配列にしている
        validateInsuredPaymentInfo(
            originAdditionalProperties = latestInsured.additionalPolicyProperties,
            inputAdditionalProperties = command.additionalPolicyProperties,
        )

        // 被保険者差分変更
        val newInsured = latestInsured.change(
            currentPolicyStatus = policy.policyStatus,
            issuedAt = policy.issuedAt,
            inputConsumerPatch = command.consumerPatch,
            inputAdditionalPolicyProperties = command.additionalPolicyProperties,
            changedAt = command.changedAt,
            remarks = command.remarks,
            userId = command.userId,
        )

        val changeResult = insuredService.changeInsured(newInsured)

        (changeResult.consumer.takeIf { it.isNaturalPerson() }?.asNaturalPerson())?.let { consumer ->
            command.toExecuteCheckConcernRequest(
                consumer.fullName,
                consumer.yomi,
                consumer.dateOfBirth,
            )?.also { request ->
                val insuredAfterChanged = insuredService.findLatestInsured(command.insuredId).validate(command.policyId)
                // Execute concern checklists
                val warnedPersons = executeCheckConcernApiService.executeCheckConcern(request)
                val insureds = warnedPersons.insureds
                handleAfterConcernChecklist(insureds, insuredAfterChanged)
            }
        }

        // 限度額チェック
        checkLimitIfNeeded(
            patch = command.consumerPatch,
            forceSaveIfCheckLimitFails = command.forceSaveIfCheckLimitFails,
            policy = policy,
            editAt = command.changedAt,
            now = currentDateTime,
            // changeResultには現在日時時点の情報が返ってきてしまうため、変更後・登録前の値を使って限度額チェックする
            editedConsumer = newInsured.consumer,
        )

        return V2InsuredChangeCommandResult(changeResult)
    }
```