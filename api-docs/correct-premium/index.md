## API
```
PUT http://localhost:8080/policies/{policy_id}/premium/correct
Content-Type: application/json
{
  "amount": 100000,
  "remarks": "CORRECTED"
}
```

## 🔄 Luồng xử lý trong `correct`

1. **Lấy policy và kiểm tra trạng thái hợp lệ**

   ```kotlin
   val policy = policyCommandService.getPolicyBy(command.policyId, command.userId)
   if (!policy.policyStatus.canCorrectPremium) {
       throw DomainInvalidArgumentException("保険料の訂正は現在のステータスでは実施できません …")
   }
   ```

    * Nếu trạng thái policy không cho phép訂正 (correction) → ném exception.

---

2. **Lấy premium mới nhất**

   ```kotlin
   val premium = premiumService.findLatestPremiumByPolicyId(command.policyId)
   ```

    * Giống `change`: không dựa vào "hiện tại" mà dựa vào bản ghi premium mới nhất (hỗ trợ future-dated).

---

3. **Tạo bản premium sau khi correction**

   ```kotlin
   val correctTo = premium.correct(
       amount = command.amount,
       correctedAt = policy.calculatePremiumCorrectionDateTime(premium.event.occurredAt),
       remarks = command.remarks,
       userId = command.userId,
   )
   ```

    * Gọi method domain `premium.correct(...)`.
    * `correctedAt` được tính bằng `policy.calculatePremiumCorrectionDateTime(...)`.
      → điểm khác biệt với `change`: ở `change` thì dùng trực tiếp `command.occurredAt`, còn ở `correct` thì correction time được tính toán dựa trên policy + occurredAt gốc của premium.

---

4. **Lưu bản correction**

   ```kotlin
   val result = premiumService.correctPremium(premium = correctTo)
   ```

    * Ghi correction vào DB.

---

5. **Trả kết quả**

   ```kotlin
   return PremiumCorrectCommandResult(result.amount, correctTo.event.occurredAt)
   ```

---

## 📌 Khác biệt chính: `change` vs `correct`

| Điểm so sánh             | `change`                                                               | `correct`                                                                                                                                   |
| ------------------------ | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------- |
| **Mục đích**             | Thay đổi phí bảo hiểm **nghiệp vụ** (business-driven change)           | Sửa lỗi/phát hiện sai lệch dữ liệu đã ghi nhận (data correction)                                                                            |
| **Điều kiện trạng thái** | `policyStatus.canChangePremium`                                        | `policyStatus.canCorrectPremium`                                                                                                            |
| **Ngày hiệu lực**        | Dùng trực tiếp `command.occurredAt` (ngày thay đổi do người dùng nhập) | Dùng `policy.calculatePremiumCorrectionDateTime(premium.event.occurredAt)` → correction time do hệ thống tính toán dựa trên bối cảnh policy |
| **Nghiệp vụ chính**      | Phản ánh một sự kiện **hợp pháp/thực tế** làm thay đổi số phí          | Điều chỉnh lại giá trị số phí đã nhập sai hoặc cần sửa chữa                                                                                 |
| **Tính chất dữ liệu**    | Ghi nhận thêm một sự kiện thay đổi phí                                 | Ghi đè/sửa chữa sự kiện đã tồn tại                                                                                                          |

---

## ⚠️ Ý nghĩa nghiệp vụ

* `change` = khi có **sự kiện nghiệp vụ thực sự** (ví dụ khách yêu cầu thay đổi điều khoản, tái đánh giá rủi ro, tăng/giảm phí).
* `correct` = khi **hệ thống/nhân viên nhập sai hoặc tính toán sai** trước đó và cần correction để phản ánh đúng.

---

👉 Nói ngắn gọn:

* **Change = thay đổi business thực sự**
* **Correct = sửa lỗi dữ liệu quá khứ**

## Code tham chiếu
```kotlin
suspend fun correct(command: PremiumCorrectCommand): PremiumCorrectCommandResult {
        val policy = policyCommandService.getPolicyBy(command.policyId, command.userId)
        if (!policy.policyStatus.canCorrectPremium) {
            throw DomainInvalidArgumentException(
                "保険料の訂正は現在のステータスでは実施できません　契約ID：${command.policyId}　ステータス：${policy.policyStatus.value}",
            )
        }

        // 未来日付の変更があり得るため、現在日時基準ではなく最新の保険料を元に訂正を行う
        val premium = premiumService.findLatestPremiumByPolicyId(command.policyId)

        val correctTo = premium.correct(
            amount = command.amount,
            correctedAt = policy.calculatePremiumCorrectionDateTime(premium.event.occurredAt),
            remarks = command.remarks,
            userId = command.userId,
        )
        val result = premiumService.correctPremium(premium = correctTo)
        return PremiumCorrectCommandResult(result.amount, correctTo.event.occurredAt)
    }
```