## API
```shell
PUT http://localhost:8080/policies/{policy_id}/riders/{rider_id}/additional-policy-properties/correct
Content-Type: application/json
{
  "rider_additional_policy_properties": [
    {
      "section": "保険受取人",
      "name": "職業",
      "value": "会社員"
    }
  ],
  "remarks": "CORRECTED"
}
```

Hàm `correctRiderAdditionalPolicyProperties` này song song với `correctRiderPremium`, nhưng đối tượng xử lý là **Rider Additional Policy Properties** (thuộc tính bổ sung của Rider) thay vì Premium.
## Breakdown theo flow nghiệp vụ

### Input

`command: RiderAdditionalPolicyPropertiesCorrectCommand` gồm:

* `policyId` – hợp đồng liên quan
* `policyRiderId` – Rider cần điều chỉnh
* `userId` – người thực hiện
* `riderAdditionalPolicyProperties` – dữ liệu bổ sung mới (bank info, wallet type, …)
* `remarks` – ghi chú

---

### Các bước xử lý

1. **Xác định thời điểm hiện tại**

   ```kotlin
   val now = currentDateTime()
   ```

2. **Lấy hợp đồng và validate quyền truy cập**

   ```kotlin
   val policy = policyCommandService.getPolicyBy(command.policyId, command.userId, now)
   ```

3. **Tính thời điểm hiệu lực correction**

    * Dùng `policy.calculateProfileCorrectionDateTime()`.
    * Đây là khác biệt quan trọng so với *change* → correction thường áp dụng tại “thời điểm hiệu chỉnh hồ sơ” (profile correction date), để sửa sai dữ liệu trong quá khứ.

   ```kotlin
   val correctedAt = policy.calculateProfileCorrectionDateTime()
   ```

4. **Lấy Rider tại thời điểm cần correction**

    * Rider gốc tại `correctedAt`.
    * Validate Rider thuộc đúng hợp đồng.

   ```kotlin
   val rider = riderService.findById(command.policyRiderId, correctedAt).validate(command.policyId)
   ```

5. **Lấy trạng thái Rider hiện tại**

    * Rider tại `now` để đảm bảo trạng thái hợp lệ.

   ```kotlin
   val currentRiderStatus = riderService.findById(command.policyRiderId, now).status
   ```

6. **Tạo bản Rider mới với correction**

    * Gọi `rider.correct(...)` với input từ command + metadata (status, correctedAt, remarks, userId).

   ```kotlin
   val newRider = rider.correct(
       currentPolicyStatus = policy.policyStatus,
       currentRiderStatus = currentRiderStatus,
       inputRiderAdditionalPolicyProperties = command.riderAdditionalPolicyProperties,
       correctedAt = correctedAt,
       remarks = command.remarks,
       userId = command.userId,
   )
   ```

7. **Lưu thay đổi**

   ```kotlin
   val result = riderService.correct(newRider)
   ```

8. **Trả về kết quả**

   ```kotlin
   return RiderAdditionalPolicyPropertiesCorrectCommandResult(result)
   ```

---

## ✅ Ý nghĩa nghiệp vụ

* **Change** = thay đổi *đúng từ thời điểm hiện tại trở đi* (thường là update business hợp lệ, future reservation).
* **Correct** = chỉnh sửa *ngược lại trong quá khứ* (thường để sửa sai thông tin đã nhập).
* Đảm bảo vẫn respect trạng thái hiện tại của hợp đồng & Rider.
* Correction dùng `calculateProfileCorrectionDateTime()` để chọn “mốc hiệu chỉnh” thay vì `changedAt` như change.


### Code tham chiếu
```kotlin
suspend fun correctRiderAdditionalPolicyProperties(
        command: RiderAdditionalPolicyPropertiesCorrectCommand,
    ): RiderAdditionalPolicyPropertiesCorrectCommandResult {
        val now = currentDateTime()

        // 契約自体を参照可能かどうかチェックしてから変更を行う
        val policy = policyCommandService.getPolicyBy(command.policyId, command.userId, now)
        val correctedAt = policy.calculateProfileCorrectionDateTime()
        val rider = riderService.findById(command.policyRiderId, correctedAt).validate(command.policyId)
        val currentRiderStatus = riderService.findById(command.policyRiderId, now).status

        val newRider = rider.correct(
            currentPolicyStatus = policy.policyStatus,
            currentRiderStatus = currentRiderStatus,
            inputRiderAdditionalPolicyProperties = command.riderAdditionalPolicyProperties,
            correctedAt = correctedAt,
            remarks = command.remarks,
            userId = command.userId,
        )

        val result = riderService.correct(newRider)
        return RiderAdditionalPolicyPropertiesCorrectCommandResult(result)
    }
```