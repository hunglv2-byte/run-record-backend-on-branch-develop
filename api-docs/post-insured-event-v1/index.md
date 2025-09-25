## API
```shell
POST http://localhost:8080/v1/policies/{policy_id}/insureds/{insured_id}/events
Content-Type: application/json
{
  "event": {
    "expired_at": "2022-04-05T00:00:00+09:00",
    "remarks": "被保険者の死亡による消滅",
    "object_type": "VANISHED"
  }
}
```

## 📌 Mục đích

Hàm này dùng để **xử lý sự kiện thay đổi trạng thái của Người được bảo hiểm (Insured)**, đặc biệt là khi người đó **biến mất/không còn trong hợp đồng** (vanish).
Nó gom nhiều event liên quan đến Insured: `Cancel`, `Invalidate`, `Surrender`, `Vanish`.

---

## 📌 Flow xử lý

1. **Lấy thông tin hợp đồng**

   ```kotlin
   val policy = policyCommandService.getPolicyBy(command.policyId, command.userId)
   ```

   → Kiểm tra xem hợp đồng có hợp lệ với người dùng hiện tại không.

---

2. **Lấy thông tin Insured theo thời điểm expiredAt**

   ```kotlin
   val insured = insuredService.findInsured(command.insuredId, command.expiredAt).validate(command.policyId)
   ```

    * Tìm **người được bảo hiểm** tại thời điểm hợp đồng hết hạn (`expiredAt`).
    * Validate Insured thuộc hợp đồng đang thao tác.

---

3. **Mapping command → sự kiện trạng thái (InsuredStatusEvent)**

   ```kotlin
   val insuredStatusEvent = when (command) {
       is InsuredCancelCommand -> InsuredStatusEvent.Canceled(command.expiredAt)
       is InsuredInvalidateCommand -> InsuredStatusEvent.Invalidated(command.expiredAt)
       is InsuredSurrenderCommand -> InsuredStatusEvent.Surrendered(command.expiredAt)
       is InsuredVanishCommand -> InsuredStatusEvent.Vanished(command.expiredAt)
   }
   ```

   → Dựa trên loại lệnh (`command`), tạo event tương ứng với **trạng thái mới của Insured** tại thời điểm `expiredAt`.

---

4. **Thực hiện update trạng thái Insured**

   ```kotlin
   val result = insuredService.vanishInsured(
       insured,
       insuredStatusEvent,
       policy.policyStatus,
       policy.appliedAt,
       policy.expiredAt,
       command.remarks,
       command.userId
   )
   ```

    * Truyền Insured, event trạng thái, và thông tin hợp đồng (trạng thái, ngày áp dụng, ngày hết hạn).
    * Ghi nhận remark + userId để audit.

---

5. **Trả về kết quả**

   ```kotlin
   return InsuredVanishCommandResult(result)
   ```

---

## 📌 Ý nghĩa nghiệp vụ

* Cho phép **cập nhật trạng thái của Người được bảo hiểm** (Insured) trong hợp đồng.
* Các trường hợp được hỗ trợ:

    * ❌ Hủy (`Cancel`)
    * 🚫 Vô hiệu hóa (`Invalidate`)
    * 🏦 Giải ước (`Surrender`)
    * 👻 Biến mất/không còn (`Vanish`)
* Dùng `expiredAt` để xác định thời điểm áp dụng event (tức là Insured sẽ được đánh dấu "biến mất" kể từ khi hợp đồng hết hiệu lực).
* Có kiểm tra tính hợp lệ của Insured và trạng thái hợp đồng trước khi thay đổi.

## Code tham chiếu
```kotlin
suspend fun vanishInsured(command: InsuredEventCommand): InsuredVanishCommandResult {
        // TODO: 契約は現在日時、expiredAtから反映している。BiTemporal的な不整合が想定されるため複雑な変更ケースでバグるかも
        val policy = policyCommandService.getPolicyBy(command.policyId, command.userId)
        val insured = insuredService.findInsured(command.insuredId, command.expiredAt).validate(command.policyId)
        val insuredStatusEvent = when (command) {
            is InsuredCancelCommand -> InsuredStatusEvent.Canceled(command.expiredAt)
            is InsuredInvalidateCommand -> InsuredStatusEvent.Invalidated(command.expiredAt)
            is InsuredSurrenderCommand -> InsuredStatusEvent.Surrendered(command.expiredAt)
            is InsuredVanishCommand -> InsuredStatusEvent.Vanished(command.expiredAt)
        }
        val result = insuredService.vanishInsured(insured, insuredStatusEvent, policy.policyStatus, policy.appliedAt, policy.expiredAt, command.remarks, command.userId)
        return InsuredVanishCommandResult(result)
    }
```