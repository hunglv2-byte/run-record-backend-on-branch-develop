## Tính phí cho từng người được bảo hiểm (Insured) – version cũ

### Input

* `validAt`: thời điểm tham chiếu để tính phí.
* `formula`: công thức tính phí (chuỗi).
* `variables`: danh sách biến số cần cho công thức.
* `baseParams`: tập tham số cơ bản (ví dụ: tuổi, giới tính, thời hạn hợp đồng…).
* `insured`: thông tin người được bảo hiểm (`InsuredParameters`), có thể kèm danh sách rider (bảo hiểm bổ sung).

---

### Các bước xử lý

1. **Hợp nhất tham số cho insured:**

    * Gọi `insured.mergeParameters(baseParams, validAt)` → tạo ra `insuredParams`:
      * [Hợp nhất tham số của người được bảo hiểm](mergeParameters/index.md).
    * Đây là tập tham số cụ thể cho người được bảo hiểm, kết hợp cả tham số gốc (`baseParams`) và tham số riêng.

2. **Trường hợp insured không có rider:**

    * Gọi `calcPremiumOld(validAt, formula, variables, insuredParams)`:
      * [Tính phí bảo hiểm (phiên bản cũ)](calcPremiumOld/index.md).
    * Nhận về `(giá trị phí, thời gian hết hạn hiệu lực)` hoặc `null`.
    * Trả về `InsuredPremium.Value(phí)` và `validTo` (mặc định vô hạn nếu không có giá trị).

3. **Trường hợp insured có rider:**

    * Khởi tạo `validTo = INFINITE_DATETIME`.
    * Với từng rider trong `insured.riders`:

        1. Hợp nhất tham số rider với `insuredParams`.
        2. Tính phí rider bằng `calcPremiumOld`:
           * [Tính phí bảo hiểm (phiên bản cũ)](calcPremiumOld/index.md).
        3. Nếu có `validTo` từ rider → cập nhật giá trị nhỏ nhất vào `validTo`.
        4. Lưu phí rider vào danh sách `RiderPremium`.
    * Trả về `InsuredPremium.HasRiders(danh sách riderPremiums)` và `validTo`.

---

### ✅ Ý nghĩa nghiệp vụ

* Mỗi **người được bảo hiểm** có thể:

    * Chỉ có hợp đồng chính (không rider) → phí được tính trực tiếp.
    * Có thêm các **rider (bảo hiểm bổ sung)** → phí được tính cho từng rider riêng, đồng thời cập nhật **thời gian hiệu lực** của toàn bộ insured bằng cách lấy **giá trị nhỏ nhất trong tất cả riders**.
* Kết quả cuối cùng cho insured gồm:

    * **Phí bảo hiểm** (có thể kèm rider).
    * **Thời điểm hết hạn hiệu lực** của phí.


## Code tham chiếu

```kotlin
suspend fun calcInsuredPremiumOld(
        validAt: OffsetDateTime,
        formula: String,
        variables: List<PremiumVariablesRecord>,
        baseParams: Map<String, Any>,
        insured: InsuredParameters,
    ): Pair<InsuredPremium, OffsetDateTime> {
        val insuredParams: Map<String, Any> = insured.mergeParameters(baseParams, validAt)

        return if (insured.riders.isEmpty()) {
            val result = calcPremiumOld(validAt, formula, variables, insuredParams)
            InsuredPremium.Value(result?.first) to (result?.second ?: INFINITE_DATETIME)
        } else {
            // NOTE: ホショウが出てきた場合は被保険者同様に関数化
            var validTo: OffsetDateTime = INFINITE_DATETIME
            val riderPremiums = insured.riders.map { rider ->
                val riderParams = rider.mergeParameters(insuredParams)
                val result = calcPremiumOld(validAt, formula, variables, riderParams)

                // valuesRecord.validToのうち、最小のものを有効日時として保持
                result?.second?.also { validTo = minOf(it, validTo) }
                // 取得した値はそのまま用いる
                RiderPremium(result?.first)
            }

            InsuredPremium.HasRiders(riderPremiums) to validTo
        }
    }
```