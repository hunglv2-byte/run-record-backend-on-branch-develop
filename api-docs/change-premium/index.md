## API
```shell
PUT http://localhost:8080/policies/{policy_id}/premium/change
Content-Type: application/json
{
  "amount": 100000,
  "changed_at": "2022-04-05T00:00:00+09:00",
  "remarks": "CHANGED"
}
```

Hàm `change` này là **xử lý thay đổi phí bảo hiểm (保険料変更)**:

---

## 🔄 Luồng xử lý

1. **Lấy hợp đồng để kiểm tra trạng thái**

   ```kotlin
   val policy = policyCommandService.getPolicyBy(command.policyId, command.userId)
   if (!policy.policyStatus.canChangePremium) {
       throw DomainInvalidArgumentException("保険料の変更は現在のステータスでは実施できません …")
   }
   ```

    * Lấy policy hiện tại bằng `policyCommandService`.
    * Nếu trạng thái policy không cho phép thay đổi phí (`canChangePremium = false`) → ném exception.

---

2. **Kiểm tra ngày kết thúc hợp đồng**

   ```kotlin
   if (policy.expiredAt!!.toInstant() < command.occurredAt.toInstant())
       throw DomainInvalidArgumentException("契約終了の保険料変更は実施できません …")
   ```

    * Nếu ngày thay đổi (`command.occurredAt`) sau ngày hết hạn hợp đồng (`policy.expiredAt`) → lỗi.
    * Giả định rằng khi đến bước này, `expiredAt` chắc chắn không `null` (vì chỉ hợp đồng “中/終了” mới cho phép).

---

3. **Lấy premium mới nhất làm cơ sở thay đổi**

   ```kotlin
   val premium = premiumService.findLatestPremiumByPolicyId(command.policyId)
   ```

    * Vì có thể tồn tại **thay đổi tương lai (予約)**, nên không dùng giá trị “hiện tại” mà dùng **bản ghi premium mới nhất**.

---

4. **Tạo premium mới từ premium cũ với thay đổi**

   ```kotlin
   val changeTo = premium.change(
       amount = command.amount,
       changedAt = command.occurredAt,
       remarks = command.remarks,
       userId = command.userId,
   )
   ```

    * `amount`: số tiền bảo hiểm mới.
    * `changedAt`: thời điểm hiệu lực của thay đổi.
    * `remarks`, `userId`: metadata.

---

5. **Lưu premium mới**

   ```kotlin
   val result = premiumService.changePremium(premium = changeTo)
   ```

    * Ghi nhận thay đổi vào DB (có thể tạo record mới hoặc cập nhật bản cũ, tuỳ cách implement service).

---

6. **Trả kết quả**

   ```kotlin
   return PremiumChangeCommandResult(result.amount, changeTo.event.occurredAt)
   ```

    * Trả về số tiền mới và ngày hiệu lực của thay đổi.

---

## 📌 Ý nghĩa nghiệp vụ

* Cho phép **thay đổi phí bảo hiểm** khi hợp đồng còn hiệu lực (hoặc đã kết thúc nhưng trong khoảng hợp lệ).

* Ngăn không cho thay đổi phí nếu:

    * Trạng thái policy không hợp lệ.
    * Ngày thay đổi nằm sau `expiredAt`.

* Dữ liệu premium luôn được lấy từ **bản ghi mới nhất**, đảm bảo hỗ trợ cả **future-dated changes** (予約).

---

## ⚠️ Lưu ý (theo TODO trong code)

* Hệ thống đang dùng cơ chế BiTemporal (ngày hiệu lực nghiệp vụ + ngày hiệu lực hệ thống).
* Hiện tại xử lý như trên có thể dẫn tới **inconsistency** trong các trường hợp phức tạp (ví dụ: thay đổi premium khi có nhiều bản ghi future cùng tồn tại).

## Code tham chiếu
```kotlin
suspend fun change(command: PremiumChangeCommand): PremiumChangeCommandResult {
        // TODO: 契約は現在日時、保険料は予約含む最新から反映している。BiTemporal的な不整合が想定されるため複雑な変更ケースでバグるかも
        val policy = policyCommandService.getPolicyBy(command.policyId, command.userId)
        if (!policy.policyStatus.canChangePremium) {
            throw DomainInvalidArgumentException(
                "保険料の変更は現在のステータスでは実施できません　契約ID：${command.policyId}　ステータス：${policy.policyStatus.value}",
            )
        }
        // 保険料変更は契約ステータスが契約中、契約終了の場合のみ実施可能なため契約終了日時がnullであることは想定しない
        if (policy.expiredAt!!.toInstant() < command.occurredAt.toInstant()) throw DomainInvalidArgumentException("契約終了の保険料変更は実施できません　契約ID：${command.policyId}　契約終了日時：${policy.expiredAt}　変更対象日時：${command.occurredAt}")

        // 未来日付の変更があり得るため、現在日時基準ではなく最新の保険料を元に変更を行う
        val premium = premiumService.findLatestPremiumByPolicyId(command.policyId)

        val changeTo = premium.change(
            amount = command.amount,
            changedAt = command.occurredAt,
            remarks = command.remarks,
            userId = command.userId,
        )
        val result = premiumService.changePremium(premium = changeTo)
        return PremiumChangeCommandResult(result.amount, changeTo.event.occurredAt)
    }
```