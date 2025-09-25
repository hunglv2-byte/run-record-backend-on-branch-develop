## API
```shell
PUT http://localhost:8080/policies/{policy_id}/riders/{rider_id}/premium/correct
Content-Type: application/json
{
  "amount": 1000,
  "remarks": "CORRECTED"
}
```

Hàm `correctRiderPremium` này khác với `changeRiderPremium` một chút: thay vì **thay đổi phí Rider tại một thời điểm hiệu lực bất kỳ**, thì nó phục vụ cho **nghiệp vụ điều chỉnh phí Rider (correction)**, thường để sửa dữ liệu do nhập sai hoặc tính toán sai trước đó.
## Nghiệp vụ: Điều chỉnh phí của điều khoản đặc biệt (Rider Premium Correction)

### Chức năng

Cho phép **sửa lại (correct)** mức phí Rider trong hợp đồng, áp dụng theo ngày điều chỉnh (correction date) do hệ thống xác định dựa trên hợp đồng.

---

### Input

* `command`: thông tin yêu cầu điều chỉnh Rider Premium, gồm:

    * `policyId`: ID hợp đồng
    * `policyRiderId`: ID Rider
    * `userId`: Người thực hiện
    * `amount`: Mức phí được điều chỉnh lại
    * `remarks`: Ghi chú (nếu có)

---

### Các bước xử lý

1. **Lấy thời điểm hiện tại**

    * `now = currentDateTime()`

2. **Xác thực quyền truy cập hợp đồng**

    * Lấy thông tin hợp đồng `policy` theo `policyId` và `userId` tại thời điểm `now`.

3. **Xác định ngày điều chỉnh (correction date)**

    * Gọi `policy.calculateProfileCorrectionDateTime()` để lấy `correctedAt`.
    * Đây là ngày hiệu lực áp dụng correction, thường khác với ngày thay đổi thông thường.

4. **Xác định trạng thái hiện tại của Rider**

    * Lấy Rider bằng `policyRiderId` tại thời điểm `now`.
    * Xác thực Rider thuộc hợp đồng (`validate(policyId)`).
    * Lấy `currentRiderStatus`.

5. **Lấy Rider Premium tại thời điểm correction**

    * Tìm bản ghi phí Rider tại `correctedAt` bằng `riderPremiumService.findById(policyRiderId, correctedAt)`.

6. **Tạo Rider Premium mới (bản điều chỉnh)**

    * Gọi `riderPremium.correct(...)` với:

        * `currentPolicyStatus`: trạng thái hợp đồng hiện tại
        * `currentRiderStatus`: trạng thái Rider hiện tại
        * `amount`: mức phí được điều chỉnh
        * `correctedAt`: ngày correction
        * `remarks`: ghi chú
        * `userId`: người điều chỉnh

7. **Áp dụng điều chỉnh**

    * Lưu Rider Premium đã điều chỉnh bằng `riderPremiumService.correct(newRiderPremium)`.

8. **Trả về kết quả**

    * Đóng gói trong `RiderPremiumCorrectCommandResult`.

---

### ✅ Ý nghĩa nghiệp vụ

* Phân biệt rõ với **thay đổi phí (change)**:

    * **Change**: thay đổi phí theo một ngày hiệu lực cụ thể (thường do người dùng nhập).
    * **Correct**: điều chỉnh lại phí theo ngày correction do hệ thống xác định, thường dùng để sửa sai dữ liệu quá khứ.
* Đảm bảo correction không phá vỡ logic trạng thái hợp đồng/Rider.
* Giữ toàn bộ lịch sử phí Rider, đồng thời cho phép track correction riêng biệt.


## Code tham chiếu
```kotlin
suspend fun correctRiderPremium(command: RiderPremiumCorrectCommand): RiderPremiumCorrectCommandResult {
        val now = currentDateTime()

        // 契約自体を参照可能かどうかチェックしてから変更を行う
        val policy = policyCommandService.getPolicyBy(command.policyId, command.userId, now)
        val correctedAt = policy.calculateProfileCorrectionDateTime()
        val currentRiderStatus = riderService.findById(command.policyRiderId, now).validate(command.policyId).status
        val riderPremium = riderPremiumService.findById(command.policyRiderId, correctedAt)

        val newRiderPremium = riderPremium.correct(
            currentPolicyStatus = policy.policyStatus,
            currentRiderStatus = currentRiderStatus,
            amount = command.amount,
            correctedAt = correctedAt,
            remarks = command.remarks,
            userId = command.userId,
        )

        val result = riderPremiumService.correct(newRiderPremium)
        return RiderPremiumCorrectCommandResult(result)
    }
```