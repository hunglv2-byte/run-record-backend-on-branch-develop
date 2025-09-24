## Lấy công thức tính phí và các biến số liên quan

### Input

* `planId`: ID của gói bảo hiểm (Plan) cần tính phí.

---

### Các bước xử lý

1. **Tìm công thức tính phí (`formulasRecord`):**

    * Truy vấn bảng **`PREMIUM_FORMULAS`** và **`PLANS`** với điều kiện `PLANS.ID = planId`.
    * Kết quả lấy ra gồm:

        * `PREMIUM_FORMULAS.ID`: ID của công thức tính phí.
        * `PREMIUM_FORMULAS.FORMULA`: nội dung công thức (dạng chuỗi).
        * `PLANS.IS_DAILY_CALCULATION_ENABLED`: cờ cho biết có bật chế độ tính phí theo ngày không.
    * Nếu không tìm thấy bản ghi phù hợp → ném ra `DomainInvalidArgumentException` (nghiệp vụ: Plan hoặc sản phẩm cha của nó không tồn tại).

2. **Tìm danh sách biến số (`variablesRecords`):**

    * Từ `formulasRecord.ID`, truy vấn bảng **`PREMIUM_VARIABLES`**.
    * Lấy toàn bộ các biến số cần thiết cho công thức tính phí (ví dụ: tuổi, giới tính, thời hạn, số người tham gia...).

3. **Trả về kết quả:**

    * Một `Pair`:

        * `formulasRecord`: thông tin công thức tính phí.
        * `variablesRecords`: danh sách biến số tương ứng.

---

### ✅ Ý nghĩa nghiệp vụ

Hàm này đảm bảo rằng khi hệ thống cần **tính phí bảo hiểm cho một plan**, nó sẽ:

* Lấy đúng **công thức tính phí** được định nghĩa cho plan đó.
* Lấy đủ **các biến số** cần thiết để thay thế vào công thức.

Nếu công thức hoặc biến số không tồn tại → hệ thống coi như dữ liệu cấu hình bị lỗi và chặn ngay (ném exception).


## Code tham chiếu

```kotlin
suspend fun getFormulaAndVariables(planId: PlanId): Pair<Record3<UUID?, String?, Boolean?>, List<PremiumVariablesRecord>> {
        val formulasRecord = jooqContext.read {
            select(
                PREMIUM_FORMULAS.ID,
                PREMIUM_FORMULAS.FORMULA,
                PLANS.IS_DAILY_CALCULATION_ENABLED,
            )
                .from(PREMIUM_FORMULAS)
                .innerJoin(PLANS)
                .on(PREMIUM_FORMULAS.PRODUCT_ID.eq(PLANS.PRODUCT_ID))
                .where(PLANS.ID.eq(planId.value))
        }
            .singleOrNull()
            ?: throw DomainInvalidArgumentException("指定されたプランまたはその親となる商品が見つかりません planId: ${planId.value}")

        // 変数取得
        val variablesRecords = jooqContext.read {
            selectFrom(PREMIUM_VARIABLES)
                .where(PREMIUM_VARIABLES.FORMULA_ID.eq(formulasRecord.read<UUID>(PREMIUM_FORMULAS.ID)))
        }.toList()

        return formulasRecord to variablesRecords
    }
```