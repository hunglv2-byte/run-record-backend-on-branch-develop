## API
```shell
PUT http://localhost:8080/v2/policies/{policy_id}/insureds/{insured_id}/correct
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
  "remarks": "CORRECTED",
  "force-save-if-check-limit-fails": false
}
```
Hàm `correctInsured` bạn đưa chính là **phiên bản “chỉnh sửa lại (訂正/correct)” của insured**, khác với `changeInsured` (thay đổi) ở chỗ nó chạy với **ngày hiệu lực “correctedAt”** (lấy từ `policy.calculateProfileCorrectionDateTime()`), dùng khi cần chỉnh sửa dữ liệu lịch sử hoặc dữ liệu đã ghi nhận trước đó.

## 🎯 Mục đích

* Cho phép **chỉnh sửa (訂正)** thông tin của một **người được bảo hiểm (Insured)** trong hợp đồng bảo hiểm.
* Sử dụng khi phát hiện thông tin nhập sai hoặc cần cập nhật hồi tố.
* Đảm bảo các kiểm tra liên quan (concern checklists, hạn mức) vẫn được áp dụng đúng sau khi chỉnh sửa.

---

## 🔄 Luồng xử lý

1. **Lấy hợp đồng hiện tại và insured tại thời điểm “correctedAt”**

   ```kotlin
   val correctedAt = policy.calculateProfileCorrectionDateTime()
   val insured = insuredService.findInsured(command.insuredId, correctedAt).validate(command.policyId)
   ```

    * `correctedAt` được tính toán từ policy → đây là mốc thời gian để chỉnh sửa dữ liệu.
    * Tìm insured tại thời điểm đó và kiểm tra có thuộc đúng policy không (`validate`).

---

2. **Tạo insured mới với dữ liệu đã chỉnh sửa**

   ```kotlin
   val newInsured = insured.correct(
       currentPolicyStatus = policy.policyStatus,
       inputConsumerPatch = command.consumerPatch,
       inputAdditionalPolicyProperties = command.additionalPolicyProperties,
       correctedAt = correctedAt,
       remarks = command.remarks,
       userId = command.userId,
   )
   ```

    * `consumerPatch`: thông tin cá nhân cần chỉnh sửa (họ tên, ngày sinh, địa chỉ...).
    * `additionalPolicyProperties`: thuộc tính bổ sung (ví dụ: thông tin thanh toán, mã khách hàng...).
    * `correctedAt`: thời điểm hiệu lực của chỉnh sửa.
    * `remarks`, `userId`: ghi chú và người thao tác.

---

3. **Ghi nhận chỉnh sửa vào DB**

   ```kotlin
   val correctResult = insuredService.correctInsured(newInsured)
   ```

---

4. **Thực hiện concern check (danh sách cảnh báo)**

   ```kotlin
   (correctResult.consumer.takeIf { it.isNaturalPerson() }?.asNaturalPerson())?.let { consumer ->
       command.toExecuteCheckConcernRequest(
           consumer.fullName,
           consumer.yomi,
           consumer.dateOfBirth,
       )?.also { request ->
           val insuredAfterCorrect = insuredService.findLatestInsured(command.insuredId).validate(command.policyId)
           val warnedPersons = executeCheckConcernApiService.executeCheckConcern(request)
           handleAfterConcernChecklist(warnedPersons.insureds, insuredAfterCorrect)
       }
   }
   ```

    * Nếu insured là **NaturalPerson** (cá nhân) → gọi API `executeCheckConcern`.
    * Nhận về danh sách **warned persons** (có cảnh báo như block auto-acceptance, cần kiểm tra thêm...).
    * Cập nhật alert trong DB thông qua `handleAfterConcernChecklist`.

---

5. **Check hạn mức bảo hiểm**

   ```kotlin
   checkLimitIfNeeded(
       patch = command.consumerPatch,
       forceSaveIfCheckLimitFails = command.forceSaveIfCheckLimitFails,
       policy = policy,
       editAt = correctedAt,
       now = currentDateTime,
       editedConsumer = newInsured.consumer,
   )
   ```

    * Đảm bảo insured sau chỉnh sửa không vượt quá hạn mức bảo hiểm.
    * Nếu vượt hạn mức nhưng flag `forceSaveIfCheckLimitFails = true`, vẫn lưu dữ liệu.

---

6. **Trả kết quả**

   ```kotlin
   return V2InsuredCorrectCommandResult(correctResult)
   ```

---

## 📌 Ý nghĩa nghiệp vụ

* **Khác với `changeInsured`**:

    * `changeInsured` → thay đổi insured từ thời điểm hiện tại hoặc trong tương lai.
    * `correctInsured` → chỉnh sửa insured hồi tố (với thời điểm hiệu lực `correctedAt`).

* **Đảm bảo tính toàn vẹn dữ liệu**:

    * Không chỉ chỉnh sửa insured, mà còn:

        * Đồng bộ cảnh báo (concern alerts).
        * Kiểm tra hạn mức.
        * Ghi nhận người thao tác và lý do chỉnh sửa.

* **Rủi ro đã note trong TODO**:

    * Vì đang xử lý theo cơ chế BiTemporal (2 chiều thời gian: hiệu lực nghiệp vụ + hiệu lực hệ thống), có thể gặp tình huống bất nhất nếu có nhiều thay đổi phức tạp.

---

👉 Nói ngắn gọn:
`correctInsured` dùng để **chỉnh sửa insured hồi tố** trong hợp đồng bảo hiểm, đảm bảo cập nhật cảnh báo và kiểm tra hạn mức đi kèm.

### Code tham chiếu
```kotlin
suspend fun correctInsured(command: V2InsuredCorrectCommand): V2InsuredCorrectCommandResult {
        val currentDateTime = currentDateTime()
        val policy = policyCommandService.getPolicyBy(command.policyId, command.userId, currentDateTime)
        val correctedAt = policy.calculateProfileCorrectionDateTime()
        val insured = insuredService.findInsured(command.insuredId, correctedAt).validate(command.policyId)

        // 被保険者差分訂正
        val newInsured = insured.correct(
            currentPolicyStatus = policy.policyStatus,
            inputConsumerPatch = command.consumerPatch,
            inputAdditionalPolicyProperties = command.additionalPolicyProperties,
            correctedAt = correctedAt,
            remarks = command.remarks,
            userId = command.userId,
        )

        val correctResult = insuredService.correctInsured(newInsured)

        (correctResult.consumer.takeIf { it.isNaturalPerson() }?.asNaturalPerson())?.let { consumer ->
            command.toExecuteCheckConcernRequest(
                consumer.fullName,
                consumer.yomi,
                consumer.dateOfBirth,
            )?.also { request ->
                val insuredAfterCorrect = insuredService.findLatestInsured(command.insuredId).validate(command.policyId)
                // Execute concern checklists
                val warnedPersons = executeCheckConcernApiService.executeCheckConcern(request)
                val insureds = warnedPersons.insureds
                handleAfterConcernChecklist(insureds, insuredAfterCorrect)
            }
        }

        // 限度額チェック
        checkLimitIfNeeded(
            patch = command.consumerPatch,
            forceSaveIfCheckLimitFails = command.forceSaveIfCheckLimitFails,
            policy = policy,
            editAt = correctedAt,
            now = currentDateTime,
            // correctResultには現在日時時点の情報が返ってきてしまうため、変更後・登録前の値を使って限度額チェックする
            editedConsumer = newInsured.consumer,
        )

        return V2InsuredCorrectCommandResult(correctResult)
    }
```