## Hợp nhất tham số của người được bảo hiểm (`mergeParameters`)

### Input

* `base`: map các tham số cơ bản (chung cho toàn bộ hợp đồng).
* `validAt`: thời điểm tham chiếu để tính (dùng để xác định tuổi…).

### Các bước xử lý

1. **Khởi tạo:**

    * Bắt đầu bằng một bản copy mutable từ `base`.

2. **Gắn tham số đặc thù cho người được bảo hiểm (chỉ áp dụng nếu là cá nhân – `NaturalPerson`):**

    * Nếu có giới tính (`sex`) → thêm vào map với key `"性別"` (giới tính).
    * Tính tuổi tại thời điểm `validAt` → nếu có giá trị thì thêm vào map với key `"年齢"` (tuổi).

3. **Gắn tham số chung:**

    * Thêm tất cả các cặp key–value trong `parameters` của insured vào map (ghi đè nếu trùng).

4. **Kết quả:**

    * Trả về map hoàn chỉnh, trong đó có đầy đủ:

        * Tham số cơ bản từ `base`.
        * Tham số đặc thù (giới tính, tuổi).
        * Tham số chung do người được bảo hiểm cung cấp.

---

### ✅ Ý nghĩa nghiệp vụ

* Hàm này tạo **tập tham số cuối cùng** để dùng cho tính phí bảo hiểm của từng người được bảo hiểm.
* Đảm bảo thông tin **cơ bản (base)** + **đặc thù (sex, tuổi)** + **tham số chung của insured** đều được hợp nhất.


## Code tham chiếu

```kotlin
 fun mergeParameters(base: Map<String, Any>, validAt: OffsetDateTime): Map<String, Any> = base.toMutableMap().apply {
        // 被保険者の固有パラメータをバインド
        if (insured is Insured.NaturalPerson) {
            insured.sex?.let { this["性別"] = it.parameterValue }
            insured.calcJstAge(validAt)?.let { age ->
                this["年齢"] = age
            }
        }

        // 被保険者の共通パラメータをバインド
        putAll(parameters)
    }
```