## Nghiệp vụ: Lấy thông tin Plan và kết quả tính phí bảo hiểm

### Input

* `planId`: mã định danh của Plan.
* `parameters`: tham số tính phí (PremiumParameters).
* `validAt`: thời điểm tham chiếu (ngày giờ tính phí).

---

### Các bước xử lý

1. **Tính phí bảo hiểm (Premium):**

    * Gọi `premiumCalculationService.calculateOld(planId, parameters, validAt)` để tính phí:
      * [Sử dụng hàm tính phí cũ (Old)](calculateOld/index.md).

2. **Lấy thông tin Plan:**

    * Gọi `planQueryService.findPlanByIdOld(planId, validAt)` để lấy thông tin chi tiết của Plan tại thời điểm `validAt`.
    * Nếu không tìm thấy Plan → ném lỗi `DomainInconsistencyException`.

      > ⚠️ Lưu ý trong code:
      >
      > * Trường hợp không lấy được plan thật sự và trường hợp plan nằm ngoài thời gian bán hàng hiện tại **không được phân biệt rõ ràng**.
      > * Điều này có thể gây hiểu nhầm rằng "phí tính được nhưng không lấy được plan" → dẫn tới ném lỗi không nhất quán.
      > * Đã có cảnh báo trong `JOINSURE-12542` để xử lý.

3. **Trả kết quả:**

    * Trả về `PlanAndCalculatedPremiumResult` gồm:

        * `plan`: thông tin chi tiết của plan.
        * `premium`: kết quả tính phí.

---

### ✅ Ý nghĩa nghiệp vụ

* Hàm này đảm bảo rằng khi cần tính phí bảo hiểm cho một Plan tại thời điểm nhất định, hệ thống **vừa tính được phí**, vừa phải **lấy được thông tin plan** để trả về cùng lúc.
* Nếu không lấy được plan, coi như dữ liệu bị **không nhất quán** và phải chặn lại bằng exception.

## Code tham chiếu

```kotlin
suspend fun getPlanAndCalculatedPremium(
        planId: PlanId,
        parameters: PremiumParameters,
        validAt: OffsetDateTime,
    ): PlanAndCalculatedPremiumResult {
        val premium = premiumCalculationService.calculateOld(planId, parameters, validAt)
        // NOTE: 本当に取得できなかった場合と、取得できるが販売期間的にNGの場合は区別できていないため要注意
        //   findPlanByIdの非推奨コメント及びJOINSURE-12542を確認すること
        //   ここでは名前から勘違いが起きた結果「保険料計算が成功しているのにプラン取得が失敗するのは異常」として不整合例外を投げしまっている
        val plan = planQueryService.findPlanByIdOld(planId, validAt)
            ?: throw DomainInconsistencyException("プラン情報取得に失敗しました id: $planId, validAt: $validAt")

        return PlanAndCalculatedPremiumResult(
            plan = plan,
            premium = premium,
        )
    }
```