## Nghiệp vụ: Lấy chi tiết một Plan theo `planId`

### Input

* `planId`: mã định danh của plan cần tìm.

---

### Các bước xử lý

1. **Truy vấn DB lấy thông tin Plan:**

    * Join nhiều bảng liên quan để lấy đủ dữ liệu:

        * `PLANS` (thông tin kế hoạch bảo hiểm chính).
        * `PRODUCTS_` (sản phẩm mà plan thuộc về).
        * `EVENT_DEFINITIONS` (định nghĩa sự kiện liên quan).
        * `PLAN_BASES` + `BASES` (hợp đồng chính và quyền lợi đi kèm).
        * `PLAN_POLICY_RENEWALS` (thông tin tái tục hợp đồng).
        * `RENEWAL_FORM_URLS` (URL form tái tục, nếu có).
        * `POLICY_LIST_CONFIGS` (cấu hình hiển thị danh sách hợp đồng, nếu có).
    * Nếu không tìm thấy → trả về `null`.

2. **Chuẩn bị dữ liệu phụ trợ:**

    * Lưu lại `planId` và `planBaseId` để dùng nhiều lần.
    * Lấy config hiển thị file PDF (Insurance Certificate UI Config) bằng `findPdfUiConfigByPlanId(planId)`.

3. **Tổng hợp thành DTO (`PlanDetailDto`):**

    * **Thông tin sản phẩm:** `productId`, `productName`.
    * **Thông tin kế hoạch:** `planId`, `planName`, `insurer`, các URL (điều khoản, disclosure, liên hệ).
    * **Thông tin tính toán:** có cho phép tính phí theo ngày (`isDailyCalculationEnabled`), có tự động chấp nhận (`isAutoAcceptanceEnabled`).
    * **Thời hạn hợp đồng:**

        * Nếu là fixed term → set `amount` + `unit`.
        * Nếu có max term → set `amount` + `unit`.
    * **Hợp đồng chính (Base):** gồm id, tên, danh sách quyền lợi (`coverages`).
    * **Hợp đồng bổ sung (Riders):** gọi `findRiders(planId)`.
    * **Cấu hình tái tục (Renewal):** có cho phép tái tục (`isRenewalEnabled`), có tự động tái tục (`isAutoRenewalEnabled`).
    * **Trạng thái Plan:** lấy từ `planStatus`.
    * **Form tái tục (RenewalFormUrl):** nếu tồn tại → trả về URL + số ngày trước khi hết hạn cho phép điền form.
    * **Cấu hình danh sách hợp đồng:** tìm thêm thuộc tính policy bổ sung (`findAdditionalPolicyPropertiesById`).
    * **UI config cho Insurance Certificate (PDF):**

        * Cho console (có hiển thị / nhãn label).
        * Cho portal (có hiển thị / nhãn label).
    * **Nút đầu hàng (Surrender button):** có hiển thị hay không (`isSurrenderButtonVisible`).

---

### ✅ Ý nghĩa nghiệp vụ

Hàm này cung cấp **toàn bộ thông tin chi tiết của một gói bảo hiểm (Plan)** để phục vụ:

* Hiển thị ở màn quản trị (console).
* Hiển thị cho người dùng (portal).
* Quản lý quyền lợi, riders, tái tục, thời hạn, các link liên quan.

## Code tham chiếu

```kotlin
override suspend fun findById(planId: PlanId): PlanDetailDto? {
        val singlePlanRecord = jooqContext.read {
            select(
                PRODUCTS_.ID,
                PRODUCTS_.NAME,
                PLANS.ID,
                PLANS.INSURER,
                PLANS.CLAUSE_URL,
                PLANS.DISCLOSURE_STATEMENT_URL,
                PLANS.CONTACT_URL,
                PLANS.NAME,
                PLANS.IS_DAILY_CALCULATION_ENABLED,
                PLAN_POLICY_RENEWALS.POLICY_RENEWAL_ID,
                PLAN_POLICY_RENEWALS.IS_RENEWAL_ENABLED,
                PLAN_POLICY_RENEWALS.IS_AUTO_RENEWAL_ENABLED,
                PLAN_POLICY_RENEWALS.AFTER_RENEWAL_PLAN_ID,
                PLAN_POLICY_RENEWALS.CHANGEOVER_AT,
                RENEWAL_FORM_URLS.URL,
                RENEWAL_FORM_URLS.AVAILABLE_DAY_BEFORE_EXPIRATION,
                EVENT_DEFINITIONS.IS_AUTO_ACCEPTANCE_ENABLED,
                PLAN_BASES.asterisk(),
                BASES.NAME,
                POLICY_LIST_CONFIGS.ADDITIONAL_POLICY_PROPERTY_IDS,
                PLANS.TERM_TYPE,
                PLANS.FIXED_TERM_AMOUNT,
                PLANS.FIXED_TERM_UNIT,
                PLANS.MAX_TERM_AMOUNT,
                PLANS.MAX_TERM_UNIT,
                PLANS.PLAN_STATUS,
                PLANS.IS_SURRENDER_BUTTON_VISIBLE,
            )
                .from(PLANS)
                .innerJoin(PRODUCTS_)
                .on(PLANS.PRODUCT_ID.eq(PRODUCTS_.ID))
                // region プランのイベント定義 (必ずある / 1件)
                .innerJoin(EVENT_DEFINITIONS)
                .on(PLANS.PRODUCT_ID.eq(EVENT_DEFINITIONS.PRODUCT_ID))
                // endregion
                // region 主契約 (必ずある / 1件)
                .innerJoin(PLAN_BASES)
                .on(PLAN_BASES.PLAN_ID.eq(PLANS.ID))
                .innerJoin(BASES)
                .on(PLAN_BASES.BASE_ID.eq(BASES.ID))
                // endregion
                // region 契約更新設定 (必ずある / 1件)
                .innerJoin(PLAN_POLICY_RENEWALS)
                .on(PLAN_POLICY_RENEWALS.PLAN_ID.eq(PLANS.ID))
                // endregion
                // region 任意更新フォームURL (ない場合がある / 1件)
                .leftJoin(RENEWAL_FORM_URLS)
                .on(RENEWAL_FORM_URLS.PLAN_ID.eq(PLANS.ID))
                // endregion
                // region 契約一覧設定 (ない場合がある / 1件)
                .leftJoin(POLICY_LIST_CONFIGS)
                .on(POLICY_LIST_CONFIGS.PLAN_ID.eq(PLANS.ID))
                // endregion
                .where(PLANS.ID.eq(planId.value))
        }
            .singleOrNull()
            ?: return null // 見つからない場合処理を打ち切る

        // 複数回アクセスするので、クエリ結果から先に取っておく
        val resultPlanId = PlanId(singlePlanRecord.read(PLANS.ID))
        val planBaseId = PlanBaseId(singlePlanRecord.read(PLAN_BASES.ID))

        // portal, consoleで2回クエリを実行しないように先に取得する
        val pdfUiConfig = findPdfUiConfigByPlanId(resultPlanId).singleOrNull()

        return PlanDetailDto(
            productId = ProductId(singlePlanRecord.read(PRODUCTS_.ID)),
            productName = singlePlanRecord.read(PRODUCTS_.NAME),
            planId = resultPlanId,
            insurer = singlePlanRecord.read(PLANS.INSURER),
            clauseUrl = singlePlanRecord.read(PLANS.CLAUSE_URL),
            disclosureStatementUrl = singlePlanRecord.read(PLANS.DISCLOSURE_STATEMENT_URL),
            contactUrl = singlePlanRecord.read(PLANS.CONTACT_URL),
            claimFormUrls = findClaimFormUrlsByPlanId(planId),
            planName = singlePlanRecord.read(PLANS.NAME),
            isDailyCalculationEnabled = singlePlanRecord.read(PLANS.IS_DAILY_CALCULATION_ENABLED),
            isAutoAcceptanceEnabled = singlePlanRecord.read(EVENT_DEFINITIONS.IS_AUTO_ACCEPTANCE_ENABLED),
            termType = singlePlanRecord.read(PLANS.TERM_TYPE),
            fixedTerm = singlePlanRecord.read<Int?>(PLANS.FIXED_TERM_AMOUNT)?.let {
                PlanDetailDto.TermDto(
                    amount = it,
                    unit = singlePlanRecord.read(PLANS.FIXED_TERM_UNIT),
                )
            },
            maxTerm = singlePlanRecord.read<Int?>(PLANS.MAX_TERM_AMOUNT)?.let {
                PlanDetailDto.TermDto(
                    amount = it,
                    unit = singlePlanRecord.read(PLANS.MAX_TERM_UNIT),
                )
            },
            planBase = PlanDetailDto.PlanBaseDto(
                id = planBaseId,
                name = singlePlanRecord.read(BASES.NAME),
                coverages = findBaseCoverages(planBaseId),
            ),
            planRiders = findRiders(planId),
            planPolicyRenewal = PlanDetailDto.PlanPolicyRenewalDto(
                isRenewalEnabled = singlePlanRecord.read(PLAN_POLICY_RENEWALS.IS_RENEWAL_ENABLED),
                isAutoRenewalEnabled = singlePlanRecord.read(PLAN_POLICY_RENEWALS.IS_AUTO_RENEWAL_ENABLED),
            ),
            planStatus = singlePlanRecord.read(PLANS.PLAN_STATUS),
            renewalFormUrl = singlePlanRecord[RENEWAL_FORM_URLS.URL]?.let {
                PlanDetailDto.RenewalFormUrlDto(
                    URI(it),
                    singlePlanRecord.read(RENEWAL_FORM_URLS.AVAILABLE_DAY_BEFORE_EXPIRATION),
                )
            },
            policyListConfigs = findAdditionalPolicyPropertiesById(
                singlePlanRecord.read<Array<UUID>?>(POLICY_LIST_CONFIGS.ADDITIONAL_POLICY_PROPERTY_IDS)?.toList(),
            ),
            consoleInsuranceCertificateUiConfig = pdfUiConfig?.let {
                PlanDetailDto.InsuranceCertificateUiConfigDto(
                    isVisible = it.read(PLAN_INSURANCE_CERTIFICATE_UI_CONFIGS.CONSOLE_IS_VISIBLE),
                    label = it.read(PLAN_INSURANCE_CERTIFICATE_UI_CONFIGS.CONSOLE_LABEL),
                )
            },
            portalInsuranceCertificateUiConfig = pdfUiConfig?.let {
                PlanDetailDto.InsuranceCertificateUiConfigDto(
                    isVisible = it.read(PLAN_INSURANCE_CERTIFICATE_UI_CONFIGS.PORTAL_IS_VISIBLE),
                    label = it.read(PLAN_INSURANCE_CERTIFICATE_UI_CONFIGS.PORTAL_LABEL),
                )
            },
            isSurrenderButtonVisible = singlePlanRecord.read(PLANS.IS_SURRENDER_BUTTON_VISIBLE),
        )
    }
```