## Nghiệp vụ: Lấy thông tin Plan và kết quả tính phí (Premium)

### Input

* `planId`: mã định danh của Plan.
* `parameter`: tham số chung để tính phí.
* `insuredConsumers`: danh sách người được bảo hiểm.
* `riderPremiumParameters`: tham số tính phí cho riders (sản phẩm bổ sung).
* `referencedAt`: thời điểm tham chiếu để tính phí.

---

### Các bước xử lý

1. **Lấy TenantId:**

    * Gọi `tenantIdGetter.getTenantId()` để xác định tenant hiện tại.

2. **Chuẩn bị Request:**

    * Tạo `GetPlanAndCalculatedPremiumV1Request` gồm:

        * `parameters`: dùng từ input `parameter`.
        * `insureds`: chuyển danh sách `insuredConsumers` thành danh sách `InsuredRequest`.

            * Mỗi insured gồm:

                * `insured`: convert từ `Consumer` sang dạng request.
                * `parameters`: hiện tại để trống (TODO trong code ghi chú rằng sau này sẽ lấy từ insured).
                * `riders`: map từ `riderPremiumParameters`. (TODO: sau này sẽ lấy riders từ insureds).
        * `validAt`: thời điểm tham chiếu.

3. **Gọi API tính phí:**

    * Gọi API `clientV1.getPlanAndCalculatedPremiumV1` với `tenantId`, `planId`, và `request:
      * [Lấy thông tin Plan và kết quả tính phí bảo hiểm](getPlanAndCalculatedPremium/index.md)
    * **Xử lý lỗi:**

        * Nếu API trả về `500 Internal Server Error` → return `null` (tránh crash).
        * Nếu lỗi khác → throw exception.

4. **Chuyển đổi Response thành DTO:**

    * Trả về `PlanAndCalculatedPremiumV1Dto` gồm:

        * `planName`: tên plan.
        * `isAutoAcceptanceEnabled`: có tự động chấp nhận hay không.
        * `premium`: thông tin tính phí gồm:

            * `premium`: phí tổng.
            * `dailyCalculatedPremium`: phí theo ngày (nếu có).
            * `insuredsPremium`: phí theo từng insured.

                * Mỗi insured có `premium`.
                * `ridersPremium`: hiện tại trả về emptyMap (TODO: riders chưa support).
            * `validTo`: thời điểm phí có hiệu lực đến.
        * `initialRenewAvailStatus`: trạng thái tái tục ban đầu (từ `planPolicyRenewal`).

---

### ✅ Ý nghĩa nghiệp vụ

Hàm này cung cấp **kết quả tính phí bảo hiểm cho một Plan cụ thể tại một thời điểm tham chiếu**, đồng thời cho biết:

* Thông tin Plan (tên, auto acceptance).
* Phí tổng, phí theo ngày, phí theo từng người được bảo hiểm.
* Cấu hình riders (hiện chưa support, để TODO).
* Thông tin tái tục hợp đồng.

## Code tham chiếu

```kotlin
override suspend fun getPlanAndCalculatedPremiumV1(
        planId: PlanId,
        parameter: PremiumParameter,
        insuredConsumers: List<Consumer>,
        riderPremiumParameters: List<PremiumParameter>,
        referencedAt: OffsetDateTime,
    ): PlanAndCalculatedPremiumV1Dto? {
        val tenantId = tenantIdGetter.getTenantId()
        val request = GetPlanAndCalculatedPremiumV1Request(
            parameters = parameter,
            insureds = insuredConsumers.map { consumer ->
                InsuredRequest(
                    insured = consumer.toInsuredRequestSlashInsuredOneOf(),
                    // TODO insuredsから計算パラメータを算出するように変更する
                    parameters = emptyMap(),
                    // TODO ridersがinsuredsに定義されたら、insureds内のridersから計算パラメータを算出するように変更する
                    riders = riderPremiumParameters.map { RiderRequest(it) },
                )
            },
            validAt = referencedAt,
        )
        val response = try {
            clientV1.invoke { this.getPlanAndCalculatedPremiumV1(tenantId, planId.value, request) }
        } catch (e: JoinsureApiException) {
            // 商品・プラン管理で保険料計算に失敗した場合に500エラーを出しているため、検知するために500でハンドリングをしている
            // ステータスコードの見直しはJOINSURE-12542で対応予定
            if (e.statusCode == HttpStatus.INTERNAL_SERVER_ERROR) return null else throw e
        }

        return PlanAndCalculatedPremiumV1Dto(
            planName = response.planName,
            isAutoAcceptanceEnabled = response.isAutoAcceptanceEnabled,
            premium = PlanAndCalculatedPremiumV1Dto.PremiumDto(
                premium = response.premium.premium,
                dailyCalculatedPremium = response.premium.dailyCalculatedPremium,
                insuredsPremium = response.premium.insuredPremiums.mapIndexed { index, insuredPremiumResponse ->
                    PlanAndCalculatedPremiumV1Dto.InsuredsPremiumDto(
                        premium = insuredPremiumResponse.premium,
                        // TODO V12時点では特約はスコープ外なので空Mapを返す
                        ridersPremium = emptyMap(),
                    )
                },
                validTo = response.premium.validTo,
            ),
            initialRenewAvailStatus = response.planPolicyRenewal.toInitialStatus(),
        )
    }
```