## Tính phí bảo hiểm (`calcPremiumOld`)

### Input

* `validAt`: thời điểm tính phí.
* `formula`: công thức tính phí (được định nghĩa ở DB).
* `variables`: danh sách biến số cần để tính (ví dụ: tuổi, giới tính, số tiền bảo hiểm, …).
* `parameters`: map tham số đầu vào (được merge từ insured + base).

### Các bước xử lý

1. **Khởi tạo:**

    * `validTo` mặc định = **vô hạn** (`INFINITE_DATETIME`).
    * Chuẩn bị `variableSet` để chứa cặp *tên biến – giá trị*.

2. **Xử lý từng biến trong `variables`:**

    * Với mỗi biến, xác định giá trị dựa trên `type`:

      a. **INPUT (giá trị đầu vào):**

        * Lấy trực tiếp từ `parameters[variable.name]`.
        * Ép sang `Int → BigDecimal`.
        * Nếu không có giá trị → return **null** (tức là không tính được phí).

      b. **TABLE (tra bảng):**

        * Gọi `getTableValueOld(validAt, variable, parameters)` để tra giá trị từ bảng phí.
        * Nếu không tìm thấy → return **null**.
        * Nếu có, đồng thời cập nhật `validTo` = **min(validTo, currentValidTo)** để đảm bảo lấy mốc hết hạn nhỏ nhất.

    * Sau khi có giá trị, đưa vào `variableSet` với key = `variable.name`.

3. **Tính phí:**

    * Sau khi tất cả biến được gán, gọi `evaluatePremium(...)` để:

        * Áp dụng công thức `formula`.
        * Dùng các biến trong `variableSet`.
        * Tính ra kết quả phí (`BigDecimal`).
        * Trả về cùng với `validTo`.

### Output

* Nếu **thiếu biến** hoặc **tra bảng thất bại** → return **null**.
* Ngược lại → return `(số tiền phí, thời điểm hết hạn hiệu lực)`

---

### ✅ Ý nghĩa nghiệp vụ

* Đây là bước **trái tim của tính phí bảo hiểm**.
* Nó lấy các tham số đã chuẩn hóa → chuyển thành biến số → tra bảng nếu cần → rồi áp dụng công thức định nghĩa sẵn để tính ra phí.
* Đồng thời xác định được **phí này còn hiệu lực đến khi nào** (dựa trên dữ liệu bảng).


## Code tham chiếu

```kotlin
suspend fun calcPremiumOld(
        validAt: OffsetDateTime,
        formula: String,
        variables: List<PremiumVariablesRecord>,
        parameters: Map<String, Any>,
    ): Pair<BigDecimal?, OffsetDateTime>? {
        var validTo: OffsetDateTime = INFINITE_DATETIME
        val variableSet = variables.fold(StaticVariableSet<BigDecimal>()) { acc, variable ->
            // 変数値の取得に失敗した場合はそれぞれ早期リターン
            val value = when (PremiumVariableType.valueOf(variable.type!!)) {
                // 入力をそのまま用いる場合、値をintと見做す
                PremiumVariableType.INPUT -> (parameters[variable.name] as Int?)?.toBigDecimal() ?: return null
                // テーブル扱いだった場合、保険料パラメータを元に値を検索する
                PremiumVariableType.TABLE -> {
                    val (value, currentValidTo) = getTableValueOld(validAt, variable, parameters) ?: return null

                    // valuesRecord.validToのうち、最小のものを有効日時として保持
                    currentValidTo?.also { validTo = minOf(it, validTo) }
                    // 取得した値はそのまま用いる
                    value
                }
            }

            // 取得した値をセット
            acc.apply { set(variable.name, value) }
        }

        return evaluatePremium(validAt, formula, variables, parameters, validTo, variableSet)
    }
```