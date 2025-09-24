## Tính phí bảo hiểm (phiên bản cũ)

### Input

* `planId`: ID của plan cần tính phí.
* `parameter`: tập tham số tính phí (`PremiumParameters`), gồm cả danh sách người được bảo hiểm (`insureds`).
* `validAt`: thời điểm tham chiếu tính phí.

---

### Các bước xử lý

1. **Lấy công thức và biến số tính phí:**

    * Gọi `getFormulaAndVariables(planId)` để lấy:
 
        * `formulasRecord`: công thức tính phí áp dụng cho plan.
        * `variablesRecords`: danh sách biến số được định nghĩa.
        * [Lấy công thức tính phí và các biến số liên quan](getFormulaAndVariables/index.md).

2. **Chuẩn bị tham số cơ bản:**

    * Tạo `baseParams` từ `parameter.createBaseParameters()`.
    * Đây là những giá trị gốc cần thiết cho công thức tính phí (ví dụ: tuổi, giới tính, thời hạn hợp đồng...).

3. **Khởi tạo thời gian hiệu lực tối đa:**

    * Đặt `validTo = INFINITE_DATETIME`.
    * Trong quá trình tính toán, sẽ cập nhật lại giá trị nhỏ nhất để biết phí này có hiệu lực đến khi nào.

4. **Tính phí cho từng người được bảo hiểm:**

    * Với mỗi `insured` trong `parameter.insureds`:

        1. Gọi `calcInsuredPremiumOld(...)` để tính phí cho người đó dựa trên công thức và biến số:
            * [Chi tiết hàm tính phí cho từng người được bảo hiểm](calcInsuredPremiumOld/index.md).
        2. Hàm này trả về:

            * `premium`: phí tính được.
            * `currentValidTo`: thời điểm phí còn hiệu lực cho người này.
        3. Cập nhật `validTo` = giá trị nhỏ nhất giữa `validTo` hiện tại và `currentValidTo`.
        4. Lưu lại kết quả `premium` cho người đó.

5. **Trả kết quả tổng hợp:**

    * Tạo `RootPremium` gồm:

        * Danh sách phí của từng người được bảo hiểm (`insuredPremiums`).
        * Thời hạn hiệu lực chung (`validTo`).
        * Thông tin plan có bật chế độ tính phí theo ngày hay không (`IS_DAILY_CALCULATION_ENABLED`).

---

### ✅ Ý nghĩa nghiệp vụ

* Đây là **hàm tính phí cũ** (Old), áp dụng công thức và biến số trực tiếp trên từng người được bảo hiểm.
* Kết quả không chỉ gồm **phí tổng hợp**, mà còn có **hiệu lực đến thời điểm nào**.
* Điểm quan trọng: phí của cả hợp đồng chỉ còn hiệu lực **tới ngày sớm nhất trong số các `validTo` của từng người**.

### Code tham chiếu

```kotlin
override suspend fun calculateOld(
        planId: PlanId,
        parameter: PremiumParameters,
        validAt: OffsetDateTime,
    ): RootPremium {
        val (formulasRecord, variablesRecords) = getFormulaAndVariables(planId)

        // 基本パラメータ
        val baseParams: Map<String, Any> = parameter.createBaseParameters()
        // この保険料がvalidAt以降いつまで有効か（以後のループ内で最小の値を保持する）
        var validTo: OffsetDateTime = INFINITE_DATETIME

        val insuredPremiums: List<InsuredPremium> = parameter.insureds.map { insured ->
            val (premium, currentValidTo) =
                calcInsuredPremiumOld(validAt, formulasRecord.read(PREMIUM_FORMULAS.FORMULA), variablesRecords, baseParams, insured)

            // valuesRecord.validToのうち、最小のものを有効日時として保持
            validTo = minOf(currentValidTo, validTo)
            // 取得した値はそのまま用いる
            premium
        }

        return RootPremium(insuredPremiums, validTo, formulasRecord.read(PLANS.IS_DAILY_CALCULATION_ENABLED))
    }
```