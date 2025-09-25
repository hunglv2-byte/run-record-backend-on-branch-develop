## API
```shell
PUT http://localhost:8080/policies/{policy_id}/riders/{rider_id}/additional-policy-properties/change
Content-Type: application/json
{
  "rider_additional_policy_properties": [
    {
      "section": "保険受取人",
      "name": "職業",
      "value": "会社員"
    }
  ],
  "updated_at": "2022-04-05T00:00:00+09:00",
  "remarks": "CHANGED"
}
```

Hàm `changeRiderAdditionalPolicyProperties` này gần giống `changeRiderPremium`, chỉ khác là nó thao tác với **Rider Additional Policy Properties** (các thuộc tính phụ của Rider trong hợp đồng, ví dụ: số tài khoản, thông tin ngân hàng, wallet type, …) thay vì Premium.
## Nghiệp vụ: Thay đổi các thuộc tính bổ sung của Rider (Rider Additional Policy Properties Change)

### Input

* `command: RiderAdditionalPolicyPropertiesChangeCommand` gồm:

    * `policyId` – hợp đồng liên quan
    * `policyRiderId` – Rider cần thay đổi
    * `userId` – người thực hiện
    * `riderAdditionalPolicyProperties` – dữ liệu bổ sung Rider (thông tin ngân hàng, ví điện tử, …)
    * `changedAt` – thời điểm hiệu lực thay đổi
    * `remarks` – ghi chú

---

### Các bước xử lý

1. **Xác định thời điểm hiện tại**

    * `now = currentDateTime()`

2. **Xác thực hợp đồng**

    * Lấy thông tin hợp đồng theo `policyId`, `userId`, và `now`.
    * Nếu hợp đồng không tồn tại hoặc không truy cập được → throw exception.

3. **Xác định Rider mới nhất**

    * Lấy Rider mới nhất bằng `findLatestById(policyRiderId)` và `validate(policyId)` để chắc chắn Rider thuộc hợp đồng.

4. **Xác định trạng thái Rider hiện tại**

    * Lấy Rider tại thời điểm `now` → `currentRiderStatus`.

5. **Tạo Rider mới với thay đổi**

    * Gọi `latestRider.change(...)` để sinh ra bản Rider mới với:

        * `currentPolicyStatus` (trạng thái hợp đồng)
        * `currentRiderStatus` (trạng thái Rider tại `now`)
        * `policyIssuedAt` / `policyExpiredAt` (giới hạn hiệu lực hợp đồng)
        * `inputRiderAdditionalPolicyProperties` (dữ liệu bổ sung mới từ command)
        * `changedAt`, `remarks`, `userId`

6. **Lưu thay đổi**

    * Gọi `riderService.change(newRider)` để lưu thông tin.

7. **Trả về kết quả**

    * Đóng gói trong `RiderAdditionalPolicyPropertiesChangeCommandResult`.

---

### ✅ Ý nghĩa nghiệp vụ

* Dùng khi cần thay đổi thông tin bổ sung của Rider (ví dụ: update thông tin tài khoản ngân hàng của người thụ hưởng Rider, thay đổi wallet type, …).
* Vẫn đảm bảo rule:

    * Hợp đồng phải ở trạng thái cho phép thay đổi Rider.
    * Rider còn hiệu lực tại thời điểm thay đổi.
* Lưu lại lịch sử thay đổi để track theo thời gian (BiTemporal).


## Code tham chiếu
```kotlin
suspend fun changeRiderAdditionalPolicyProperties(
        command: RiderAdditionalPolicyPropertiesChangeCommand,
    ): RiderAdditionalPolicyPropertiesChangeCommandResult {
        val now = currentDateTime()

        // 契約自体を参照可能かどうかチェックしてから変更を行う
        // TODO: 契約は現在日時、特約は予約含む最新から反映している。BiTemporal的な不整合が想定されるため複雑な変更ケースでバグるかも
        val policy = policyCommandService.getPolicyBy(command.policyId, command.userId, now)
        val latestRider = riderService.findLatestById(command.policyRiderId).validate(command.policyId)
        val currentRiderStatus = riderService.findById(command.policyRiderId, now).status

        val newRider = latestRider.change(
            currentPolicyStatus = policy.policyStatus,
            currentRiderStatus = currentRiderStatus,
            policyIssuedAt = policy.issuedAt,
            policyExpiredAt = policy.expiredAt,
            inputRiderAdditionalPolicyProperties = command.riderAdditionalPolicyProperties,
            changedAt = command.changedAt,
            remarks = command.remarks,
            userId = command.userId,
        )

        val result = riderService.change(newRider)
        return RiderAdditionalPolicyPropertiesChangeCommandResult(result)
    }
```

