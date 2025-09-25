## Cập nhật trạng thái điều khoản đặc biệt (Rider)

### Chức năng

Sau khi cập nhật trạng thái Rider, hệ thống trả về **thông tin Rider tại thời điểm hiện tại**
(ngay cả khi cập nhật được đăng ký cho thời điểm tương lai).

---

### Input

* `policyRiderId`: ID của Rider cần thay đổi
* `riderStatusEvent`: Sự kiện trạng thái Rider (Canceled, Invalidated, Surrendered, Vanished)
* `currentPolicyStatus`: Trạng thái hợp đồng hiện tại
* `policyExpiredAt`: Ngày hết hạn của hợp đồng (có thể null)

---

### Các bước xử lý

1. **Kiểm tra tính hợp lệ theo trạng thái hợp đồng**

    * Nếu trạng thái hợp đồng hiện tại (`currentPolicyStatus`) **không cho phép thay đổi Rider**, thì từ chối:
      → Ném lỗi: `"特約ステータスの変更は現在の契約ステータスでは実施できません"`

2. **Kiểm tra tính hợp lệ theo ngày hết hạn hợp đồng**

    * Nếu `occurredAt` (ngày hiệu lực thay đổi Rider) **sau ngày hết hạn hợp đồng** (`policyExpiredAt`) → từ chối:
      → Ném lỗi: `"特約ステータスの変更は契約終了日時よりも未来日時では実施できません"`

3. **Tìm Rider tại thời điểm xảy ra sự kiện**

    * Gọi `riderRepository.findById(policyRiderId, riderStatusEvent.occurredAt)`
    * Lưu ý: ngay cả khi thay đổi là **future reservation (tương lai)**, kết quả trả về vẫn là thông tin Rider **tại thời điểm hiện tại**.

4. **Cập nhật trạng thái Rider**

    * Gọi `rider.updateRiderStatus(riderStatusEvent)` để áp dụng sự kiện.
    * Lưu lại thay đổi qua `riderRepository.updateRiderStatus(...)`.

5. **Xử lý đặc biệt khi Rider “消滅 (Vanished)”**

    * Nếu Rider biến mất, cần xóa vật lý (physical delete) Rider ở hợp đồng kế tiếp.
    * Đây là xử lý tạm thời (workaround).
    * Trong tương lai sẽ được thay bằng **xóa logic BiTemporal** (ghi nhận cả lịch sử).

6. **Trả về kết quả**

    * Trả về `RiderAggregate` mới nhất (đã cập nhật) tại **thời điểm hiện tại**.

---

### ✅ Ý nghĩa nghiệp vụ

* Đảm bảo rằng trạng thái Rider chỉ được thay đổi khi hợp đồng cho phép và trong phạm vi thời gian hợp lệ.
* Ngay cả khi cập nhật trạng thái ở tương lai, **kết quả trả về vẫn là Rider tại thời điểm hiện tại**, để đảm bảo tính nhất quán khi sử dụng trong màn hình hoặc API.
* Có xử lý đặc biệt với Rider biến mất (Vanished): **xóa Rider ở hợp đồng tiếp theo** để tránh dữ liệu dư thừa.


### Code tham chiếu
```kotlin
/**
     * 特約ステータスを更新後、現在日時時点の特約を返す（= 未来予約だったとしても、返却されるのは現在日時時点の情報）
     */
    suspend fun updateRiderStatus(
        policyRiderId: PolicyRiderId,
        riderStatusEvent: RiderStatusEvent,
        currentPolicyStatus: PolicyStatus,
        policyExpiredAt: OffsetDateTime?,
    ): RiderAggregate {
        // 契約ステータスによっては変更は不可
        if (!currentPolicyStatus.canChangeRiderStatus) {
            throw DomainInvalidArgumentException("特約ステータスの変更は現在の契約ステータス（${currentPolicyStatus.value}）では実施できません。特約ID=$policyRiderId")
        }
        // 契約終了日時より後の変更は不可　※変更可能な契約ステータスでは契約終了日時が存在する
        if (policyExpiredAt!!.toInstant() < riderStatusEvent.occurredAt.toInstant()) throw DomainInvalidArgumentException("特約ステータスの変更は契約終了日時よりも未来日時では実施できません。特約ID=$policyRiderId、契約終了日時：$policyExpiredAt 変更有効日時：${riderStatusEvent.occurredAt}")
        val rider = riderRepository.findById(policyRiderId, riderStatusEvent.occurredAt)
        // 負債で、未来予約であったとしても返ってくるのは現在日時時点の情報（find結果）になっている
        val result = riderRepository.updateRiderStatus(rider.updateRiderStatus(riderStatusEvent))
        // 特約が消滅した場合に後契約の特約を物理削除する
        // これは仮対応での物理削除であり、将来的にはBiTemporalでの論理削除を行う
        physicalDeleteNextPolicyRiderIfVanished(result.policyId, result.policyRiderId)

        return result
    }
```