Hàm `validateInsuredPaymentInfo` này có thể coi là một **business rule validation layer** dành riêng cho **payment info của 被保険者 (Insured)**.

---

### 1. **Mục đích**

* Đảm bảo khi thay đổi `AdditionalPolicyProperties` của Insured, các thông tin liên quan đến **thanh toán (payment info)** được kiểm tra hợp lệ trước khi commit vào hệ thống.
* Chỉ chạy khi **tenant** thuộc nhóm đặc biệt (`allowedTenants`).

---

### 2. **Luồng xử lý**

1. **Tenant check**

   ```kotlin
   if (!allowedTenants.contains(tenantIdGetter.getTenantId())) return
   ```

   → Nếu không phải tenant thuộc scope, bỏ qua hoàn toàn (để tránh lỗi cho các tenant khác không dùng rule này).

2. **Check input có liên quan không**

   ```kotlin
   if (!inputAdditionalProperties.any { paymentInfoPropertyKeys.contains(it.name) }) return
   ```

   → Nếu người dùng không thay đổi gì liên quan đến payment info (`cityCode, dorecaId, bank info, walletTypeId`), thì không validate.

3. **Tạo dữ liệu merged để validate**

   ```kotlin
   val changedAdditionalPropertiesMap = originAdditionalProperties.toMap() + inputAdditionalProperties.toMap()
   ```

   → Kết hợp `origin` + `input` để lấy snapshot sau thay đổi.
   (Trong đó `input` sẽ override `origin` nếu cùng key).

4. **Validation logic**

    * `validateCityCode`: kiểm tra mã thành phố hợp lệ.
    * `validateDorecaId`: kiểm tra Doreca ID hợp lệ.
    * `validateBankInfoAndEmoneyInfo`: kiểm tra consistency giữa bank account info và ví điện tử (emoney info).
      → Ví dụ: Nếu `walletTypeId` ≠ "", thì bank info có thể bỏ qua. Nếu bank info được nhập thì phải đầy đủ (bankCode, branch, số tài khoản, loại tài khoản, tên chủ tài khoản).

---

### 3. **Ý nghĩa business**

* Rule này đảm bảo **chỉ Insured ở tenant đặc biệt (ví dụ MSAD-INS)** mới cần validate kỹ payment info.
* Tránh case thiếu data hoặc data không consistent gây lỗi khi **trích nợ tự động / kết nối với hệ thống ngoài (doreca, ngân hàng, ví điện tử)**.
* Đặt trong `changeInsured` flow để **ngăn dữ liệu xấu ngay tại command layer**, thay vì đợi đến lúc billing mới phát hiện.


### Code tham chiếu
```kotlin
internal suspend fun validateInsuredPaymentInfo(
        originAdditionalProperties: AdditionalPolicyProperties,
        inputAdditionalProperties: AdditionalPolicyProperties,
    ) {
        // 対象テナントでなければ何もしない
        if (!allowedTenants.contains(tenantIdGetter.getTenantId())) return

        val paymentInfoPropertyKeys = listOf(
            PROPERTY_KEY_CITY_CODE,
            PROPERTY_KEY_DORECA_ID,
            PROPERTY_KEY_BANK_CODE,
            PROPERTY_KEY_BANK_BRANCH_CODE,
            PROPERTY_KEY_BANK_ACCOUNT_NUMBER,
            PROPERTY_KEY_BANK_ACCOUNT_TYPE,
            PROPERTY_KEY_BANK_ACCOUNT_NAME,
            PROPERTY_KEY_WALLET_TYPE_ID,
        )

        // インプットに対象のキーが含まれない場合、バリデーションはスキップする
        if (!inputAdditionalProperties.any { paymentInfoPropertyKeys.contains(it.name) }) return

        val changedAdditionalPropertiesMap = originAdditionalProperties.toMap() + inputAdditionalProperties.toMap()

        // cityCodeのバリデーション
        changedAdditionalPropertiesMap[PROPERTY_KEY_CITY_CODE]?.let {
            validateCityCode(it)
        }

        // dorecaIdのバリデーション
        changedAdditionalPropertiesMap[PROPERTY_KEY_DORECA_ID]?.let {
            validateDorecaId(it)
        }

        // 支払い口座のバリデーション
        validateBankInfoAndEmoneyInfo(
            walletTypeId = changedAdditionalPropertiesMap[PROPERTY_KEY_WALLET_TYPE_ID] ?: "",
            bankCode = changedAdditionalPropertiesMap[PROPERTY_KEY_BANK_CODE] ?: "",
            bankBranchCode = changedAdditionalPropertiesMap[PROPERTY_KEY_BANK_BRANCH_CODE] ?: "",
            bankAccountNumber = changedAdditionalPropertiesMap[PROPERTY_KEY_BANK_ACCOUNT_NUMBER] ?: "",
            bankAccountType = changedAdditionalPropertiesMap[PROPERTY_KEY_BANK_ACCOUNT_TYPE] ?: "",
            bankAccountName = changedAdditionalPropertiesMap[PROPERTY_KEY_BANK_ACCOUNT_NAME] ?: "",
        )
    }
```