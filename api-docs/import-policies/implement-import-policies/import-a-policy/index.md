## Nghiệp vụ: Import 1 hợp đồng bảo hiểm (Policy)

### 1. Xác minh dữ liệu đầu vào

* **Kiểm tra quyền user:**

    * Mã đại lý (**agencyCode**) và mã văn phòng (**salesOfficeCode**) trong bản ghi phải nằm trong phạm vi tham chiếu (reference scope) của user:
      * [Xác minh đại lý và văn phòng giao dịch của bản ghi hợp đồng](validateAgencySalesOfficeCode/index.md)

* **Kiểm tra tồn tại:**

    * Xác minh agency/sales office đó có tồn tại trong hệ thống (qua `cache`):
      * [Kiểm tra sự tồn tại của đại lý/văn phòng](validateExistsAgencySalesOffice/index.md)

* **Lấy thông tin sản phẩm (plan):**

    * Truy xuất thông tin plan:
      * [Lấy chi tiết một Plan theo `planId`](findById/index.md)
    * Tính toán phí bảo hiểm (premium):
      * [Lấy thông tin Plan và kết quả tính phí (Premium)](getPlanAndCalculatedPremiumV1/index.md)
    * Việc lấy plan bị lặp lại với bước validation, nhưng hiện chưa có API chỉ lấy premium riêng nên phải làm như vậy.

* **Phát sinh số hợp đồng (policy number):**

    * Sinh ra số hợp đồng mới (policyNumber) trước khi bắt đầu lưu dữ liệu.

---

### 2. Tạo các đối tượng domain cần thiết

* Từ dữ liệu nhập (`command`), tạo **PolicyAggregate** chứa thông tin hợp đồng.

---

### 3. Đăng ký hợp đồng trong 1 transaction

Thực hiện tất cả các bước dưới đây trong một giao dịch (transaction):

1. **Đăng ký hợp đồng (policy):**

    * Tạo bản ghi hợp đồng chính.

2. **Đăng ký bên mua bảo hiểm (policyholder):**

    * Gắn thông tin người mua vào hợp đồng.

3. **Đăng ký thông tin tái tục (policyRenewal):**

    * Lưu dữ liệu về tình trạng tái tục (initial renewal status).

4. **Đăng ký quyền lợi bảo hiểm (coverage):**

    * Tạo các coverages theo sản phẩm (plan) và dữ liệu hợp đồng.

5. **Đăng ký thanh toán (payment):**

    * Tạo phương thức thanh toán mặc định: **một lần (lumpsum)**, bằng **external means**.

6. **Đăng ký phí bảo hiểm (premium):**

    * Tạo bản ghi premium gắn với hợp đồng.

7. **Đăng ký người được bảo hiểm (insureds):**

    * Lưu thông tin insureds (người được bảo hiểm) vào hợp đồng.

8. **Xử lý trạng thái hợp đồng:**

    * **Accept Policy:** Đánh dấu hợp đồng được chấp nhận.
    * **First Premium Paid:** Đánh dấu đã thu phí bảo hiểm đầu tiên.
    * **Confirm Premium:** Xác nhận phí bảo hiểm hàng tháng.
    * **Activate Policy:** Kích hoạt hợp đồng (bắt đầu có hiệu lực).

9. **Tạo route thanh toán + gửi request thu phí đầu tiên:**

    * Tạo thông tin về phương thức thanh toán (payment route).
    * Gửi yêu cầu thu phí đầu tiên qua API Payment.

---

## ✅ Tóm tắt luồng nghiệp vụ

1. **Xác minh** dữ liệu (scope, tồn tại agency/sales office, plan, premium).
2. **Khởi tạo** policy aggregate và số hợp đồng.
3. **Đăng ký đầy đủ thông tin hợp đồng** trong 1 transaction:

    * Policy, Policyholder, Renewal, Coverage, Payment, Premium, Insured.
4. **Chuyển trạng thái hợp đồng** qua các bước: Accept → First Paid → Confirm Premium → Activate.
5. **Gửi yêu cầu thanh toán** cho phí bảo hiểm đầu tiên.

### Code tham chiếu 

```kotlin  
suspend fun importPolicy(referenceScopes: ReferenceScopes.ConsoleUser, command: ImportPoliciesCommand, now: OffsetDateTime, cache: ApiCache) {
        // レコードの代理店コード/営業所コードがコンソールユーザの参照権限内かどうかを確認
        validateAgencySalesOfficeCode(referenceScopes, command.agencyCode, command.salesOfficeCode)

        // レコードの代理店コード/営業所コードが存在するかどうかを確認
        cache.validateExistsAgencySalesOffice(command.agencyCode, command.salesOfficeCode)

        val plan = cache.findByPlanId(command.planId)

        // プラン・保険料取得(取得処理のため、トランザクション外かつ証券番号発番前に行う)
        // プランのバリデーションでもプラン取得をしており、処理が重複しているが保険料のみを取得するAPIがないため、現在の実装になっている
        // 性能に問題がある場合は、APIを追加すること
        val planAndCalculatedPremium = getPlanAndCalculatedPremiumV1(command)

        val policyNumber = transactionalOperator.transactional { policyNumberFactory.generateOld() }

        // policyAggregate作成
        val policy = command.toPolicyAggregate(referenceScopes.userId, plan.getFixedTerm(), policyNumber, now)

        transactionalOperator.transactional {
            // policy作成
            @Suppress("DEPRECATION_ERROR") // この文脈では確実に新規登録なので許容する
            policyService.optimizedCreatePolicy(policy)

            // policyholder作成
            @Suppress("DEPRECATION_ERROR") // この文脈では確実に新規登録なので許容する
            policyholderService.optimizedCreatePolicyholder(
                command.policyholder.toAggregate(policy.id, policy.appliedAt),
            )

            // policyRenewal作成
            policyRenewalService.save(
                PolicyRenewalAggregate.create(
                    policyId = policy.id,
                    appliedAt = policy.appliedAt,
                    initialStatus = planAndCalculatedPremium.initialRenewAvailStatus,
                ),
            )

            // coverage作成
            coverageService.createCoverages(command.baseCoverages.toAggregates(policy.id, plan, policy.appliedAt))

            // payment作成
            paymentService.createPayment(
                PaymentAggregate.create(
                    policyId = policy.id,
                    frequency = PaymentFrequency.LUMPSUM,
                    means = PaymentMeansType.EXTERNAL,
                ),
            )

            // premium作成
            val premium = planAndCalculatedPremium.toPremiumAggregate(policy.id, policy.appliedAt)
            premiumService.createPremiumOld(premium)

            // insured作成
            @Suppress("DEPRECATION_ERROR") // この文脈では確実に新規登録なので許容する
            insuredService.optimizedCreateInsureds(
                InsuredAggregate.createAll(
                    policyId = policy.id,
                    appliedAt = policy.appliedAt,
                    insureds = command.insureds.toParams(),
                ),
            )

            // 承諾処理
            val accepted = policyService.acceptPolicy(policy, policy.appliedAt, null, null)

            // 初回保険料収納成功処理
            val paid = policyService.firstPremiumPaidPolicy(
                policy = accepted,
                paidAt = policy.appliedAt,
                issuedAt = command.issuedAt,
                isDailyCalculationEnabled = false,
            )

            // 月額保険料確定処理
            premiumService.confirmPremiumOld(
                premium.confirm(
                    amount = premium.amount,
                    confirmedAt = policy.provisionalIssuedAt!!,
                ),
            )

            // 契約開始処理
            policyService.activatePolicy(
                policy = paid,
                issuedAt = command.issuedAt,
            )

            // 払込経路作成&初回保険料収納リクエスト
            paymentApiService.importPayment(policy.rootPolicyId, premium.amount, policy.appliedAt, policy.appliedAt)
        }
    }
```