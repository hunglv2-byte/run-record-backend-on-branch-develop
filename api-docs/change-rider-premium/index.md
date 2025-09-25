## API
```shell
PUT http://localhost:8080/policies/{policy_id}/riders/{rider_id}/premium/change
Content-Type: application/json
{
  "amount": 1000,
  "changed_at": "2022-04-05T00:00:00+09:00",
  "remarks": "CHANGED"
}
```

## Nghiệp vụ: Thay đổi phí của điều khoản đặc biệt (Rider Premium)

### Chức năng

Cho phép thay đổi **mức phí bảo hiểm** của một Rider trong hợp đồng, đảm bảo tuân thủ trạng thái hợp đồng và Rider tại thời điểm hiện tại.

---

### Input

* `command`: thông tin yêu cầu thay đổi Rider Premium, bao gồm:

    * `policyId`: ID hợp đồng
    * `policyRiderId`: ID Rider
    * `userId`: Người thực hiện
    * `amount`: Mức phí mới
    * `changedAt`: Ngày hiệu lực của thay đổi
    * `remarks`: Ghi chú (nếu có)

---

### Các bước xử lý

1. **Lấy thời điểm hiện tại**

    * `now = currentDateTime()`

2. **Xác thực quyền truy cập hợp đồng**

    * Lấy thông tin hợp đồng `policy` bằng `policyId` và `userId`.
    * Chỉ khi người dùng có quyền xem hợp đồng thì mới cho phép thay đổi.
    * ⚠️ Ghi chú kỹ thuật:

        * Hợp đồng lấy theo thời điểm hiện tại (`now`).
        * Rider lấy theo bản ghi mới nhất (bao gồm cả lịch hẹn trong tương lai).
        * Điều này có thể gây **inconsistency BiTemporal** trong các trường hợp thay đổi phức tạp.

3. **Xác định trạng thái hiện tại của Rider**

    * Lấy Rider bằng `policyRiderId` tại thời điểm `now`.
    * Xác thực Rider thuộc về hợp đồng (`validate(policyId)`).
    * Lấy `currentRiderStatus`.

4. **Lấy phí Rider gần nhất**

    * Từ `riderPremiumService.findLatestById(policyRiderId)`

5. **Tạo Rider Premium mới**

    * Gọi `latestRiderPremium.change(...)` với các tham số:

        * `currentPolicyStatus`: trạng thái hợp đồng hiện tại
        * `currentRiderStatus`: trạng thái Rider hiện tại
        * `policyIssuedAt`, `policyExpiredAt`: thời hạn hiệu lực hợp đồng
        * `amount`: mức phí mới
        * `changedAt`: ngày thay đổi có hiệu lực
        * `remarks`: ghi chú
        * `userId`: người thay đổi

6. **Áp dụng thay đổi**

    * Lưu lại thay đổi Rider Premium thông qua `riderPremiumService.change(newRiderPremium)`.

7. **Trả về kết quả**

    * Kết quả được đóng gói trong `RiderPremiumChangeCommandResult`.

---

### ✅ Ý nghĩa nghiệp vụ

* Đảm bảo rằng việc thay đổi phí Rider được kiểm soát theo **trạng thái hợp đồng và trạng thái Rider**.
* Cho phép thay đổi có ngày hiệu lực (có thể ở hiện tại hoặc tương lai).
* Giữ lại lịch sử phí Rider thông qua cơ chế `latest → change → save`.
* Có cảnh báo tiềm ẩn về **bất nhất dữ liệu thời gian (BiTemporal inconsistency)** khi hợp đồng và Rider được tham chiếu theo thời điểm khác nhau.


## Code tham chiếu

```kotlin
suspend fun changeRiderPremium(command: RiderPremiumChangeCommand): RiderPremiumChangeCommandResult {
        val now = currentDateTime()

        // 契約自体を参照可能かどうかチェックしてから変更を行う
        // TODO: 契約は現在日時、特約は予約含む最新から反映している。BiTemporal的な不整合が想定されるため複雑な変更ケースでバグるかも
        val policy = policyCommandService.getPolicyBy(command.policyId, command.userId, now)
        val currentRiderStatus = riderService.findById(command.policyRiderId, now).validate(command.policyId).status
        val latestRiderPremium = riderPremiumService.findLatestById(command.policyRiderId)

        val newRiderPremium = latestRiderPremium.change(
            currentPolicyStatus = policy.policyStatus,
            currentRiderStatus = currentRiderStatus,
            policyIssuedAt = policy.issuedAt,
            policyExpiredAt = policy.expiredAt,
            amount = command.amount,
            changedAt = command.changedAt,
            remarks = command.remarks,
            userId = command.userId,
        )

        val result = riderPremiumService.change(newRiderPremium)
        return RiderPremiumChangeCommandResult(result)
    }
```