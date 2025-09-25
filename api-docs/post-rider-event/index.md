### API
```shell
POST http://localhost:8080/policies/{policy_id}/riders/{rider_id}/events
Content-Type: application/json
{
  "event": {
    "expired_at": "2022-04-05T00:00:00+09:00",
    "remarks": "契約者申し出による解約",
    "object_type": "SURRENDERED"
  }
}
```

## Nghiệp vụ: Áp dụng sự kiện thay đổi trạng thái điều khoản đặc biệt (Rider)

### Input

* `command: RiderEventCommand`
  (có thể là: `RiderCancelCommand`, `RiderInvalidateCommand`, `RiderSurrenderCommand`, `RiderVanishCommand`)

### Các bước xử lý

1. **Lấy hợp đồng bảo hiểm (Policy)**

    * Tìm policy từ `policyCommandService.getPolicyBy(policyId, userId)` dựa trên thông tin trong `command`.
    * Mục đích: kiểm tra người dùng có quyền tham chiếu hợp đồng này trước khi cho phép thay đổi.

2. **Xác định thời điểm thay đổi trạng thái**

    * Gọi `policy.calculateRiderStatusChangeDateTime(command.occurredAt)` để tính **thời điểm phát sinh sự kiện**.
    * Điều này đảm bảo rằng ngày hiệu lực của sự kiện Rider phù hợp với thời gian hợp đồng.

3. **Tạo sự kiện trạng thái Rider (`RiderStatusEvent`)**

    * Tùy vào loại command:

        * `RiderCancelCommand` → trạng thái = **Canceled**
        * `RiderInvalidateCommand` → trạng thái = **Invalidated**
        * `RiderSurrenderCommand` → trạng thái = **Surrendered**
        * `RiderVanishCommand` → trạng thái = **Vanished**
    * Mỗi sự kiện bao gồm:

        * `occurredAt`: thời điểm xảy ra
        * `remarks`: ghi chú từ người dùng
        * `userId`: người thực hiện thao tác

4. **Cập nhật trạng thái điều khoản Rider**

    * Gọi `riderService.updateRiderStatus` với các tham số:

        * `policyRiderId` (id của Rider cần thay đổi)
        * `riderStatusEvent` (sự kiện vừa tạo)
        * `policy.policyStatus` (trạng thái hợp đồng hiện tại)
        * `policy.expiredAt` (ngày hết hạn hợp đồng)
        * [Cập nhật trạng thái điều khoản đặc biệt (Rider)](updateRiderStatus/index.md)

5. **Validate sau khi cập nhật**

    * Gọi `.validate(command.policyId)` để đảm bảo dữ liệu sau khi cập nhật vẫn hợp lệ.
    * (Chú thích trong code: muốn validate trước khi thay đổi, nhưng do phải có `RiderAggregate` sau update mới kiểm tra được → nên validate sau).

---

### ✅ Ý nghĩa nghiệp vụ

* Đây là quy trình **xử lý các sự kiện liên quan đến điều khoản bổ sung (Rider)** trong hợp đồng bảo hiểm.
* Các sự kiện có thể là: hủy bỏ, vô hiệu, giải ước, hoặc biến mất.
* Quy trình đảm bảo:

    * **Kiểm tra quyền truy cập hợp đồng** trước khi thay đổi.
    * **Xác định chính xác ngày hiệu lực** thay đổi trạng thái Rider.
    * **Ghi nhận sự kiện đầy đủ** (thời gian, người thao tác, ghi chú).
    * **Cập nhật và xác thực tính hợp lệ** của dữ liệu sau thay đổi.


### Code tham chiếu
```kotlin
suspend fun applyRiderEvent(
        command: RiderEventCommand,
    ) = policyCommandService.getPolicyBy(command.policyId, command.userId).let { policy ->
        // 契約自体を参照可能かどうかチェックしてからステータス更新を行う
        val occurredAt = policy.calculateRiderStatusChangeDateTime(command.occurredAt)
        val riderStatusEvent = when (command) {
            is RiderCancelCommand -> RiderStatusEvent.Canceled(occurredAt, command.remarks, command.userId)
            is RiderInvalidateCommand -> RiderStatusEvent.Invalidated(occurredAt, command.remarks, command.userId)
            is RiderSurrenderCommand -> RiderStatusEvent.Surrendered(occurredAt, command.remarks, command.userId)
            is RiderVanishCommand -> RiderStatusEvent.Vanished(occurredAt, command.remarks, command.userId)
        }
        riderService.updateRiderStatus(command.policyRiderId, riderStatusEvent, policy.policyStatus, policy.expiredAt)
    }.validate(command.policyId) // 変更前にチェックしたいが変更後でなければRiderAggregateが取得できないため、ここでチェックする
```