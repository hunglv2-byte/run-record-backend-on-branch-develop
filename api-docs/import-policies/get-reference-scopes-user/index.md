### Nghiệp vụ: Lấy phạm vi tham chiếu (Reference Scopes) của User

Khi truyền vào `userId`, hệ thống thực hiện:

1. **Truy vấn thông tin người dùng**

    * Lấy dữ liệu từ bảng `USERS`, kèm thông tin liên kết với `AGENCIES` và `SALES_OFFICES`.
    * Ưu tiên bản ghi mới nhất (`VALID_FROM` mới nhất), bất kể có bị đánh dấu xóa hay không.

2. **Xác định loại phạm vi tham chiếu**

    * Dựa vào dữ liệu lấy được, hệ thống kiểm tra theo thứ tự:

   **a. Người dùng thuộc công ty bảo hiểm và có thiết lập phạm vi tham chiếu (Insurer Reference Scope):**

    * Nếu cột `INSURER_REFERENCE_SCOPE_ID` có giá trị.
    * Khi đó hệ thống tìm danh sách các phạm vi được phép tham chiếu (`referableScopes`).
    * Kết quả trả về: `UserReferenceScopesDto.Insurer(referableScopes)`

   **b. Người dùng thuộc công ty bảo hiểm nhưng không có Agency (người dùng cấp cao nhất / toàn quyền):**

    * Nếu `AGENCY_ID` = null.
    * Kết quả trả về: `UserReferenceScopesDto.Insurer(null)` (nghĩa là không giới hạn).

   **c. Người dùng thuộc Agency hoặc Sales Office:**

    * Nếu `AGENCY_ID` có giá trị.
    * Lấy `agencyId`, `agencyCode`, và (nếu có) `salesOfficeId`, `salesOfficeCode`.
    * Xác định danh sách mã liên kết (shared alignment codes) mà user được quyền tham chiếu.
    * Kết quả trả về: `UserReferenceScopesDto.BelongToAgency(sharedAlignmentCodes)`

3. **Trường hợp không tìm thấy user hợp lệ:**

    * Nếu truy vấn không trả về bản ghi nào → trả về `null`.

---

### ✅ Tóm gọn nghiệp vụ

* **User thuộc công ty bảo hiểm + có scope cụ thể** → trả về danh sách scope.
* **User thuộc công ty bảo hiểm + không gắn agency** → có quyền rộng nhất (không giới hạn).
* **User thuộc agency/sales office** → trả về phạm vi gắn với agency/sales office đó.
* **Không tìm thấy user** → trả về `null`.

### Code tham chiếu

```kotlin
override suspend fun findUserReferenceScopesById(userId: UserId): UserReferenceScopesDto? {
        val user = jooqContext.read {
            select(
                USERS.INSURER_REFERENCE_SCOPE_ID,
                AGENCIES.AGENCY_ID,
                AGENCIES.CODE,
                SALES_OFFICES.SALES_OFFICE_ID,
                SALES_OFFICES.CODE,
            )
                .from(USERS)
                .leftJoin(AGENCIES)
                .on(USERS.AGENCY_ID.eq(AGENCIES.AGENCY_ID))
                .leftJoin(SALES_OFFICES)
                .on(USERS.SALES_OFFICE_ID.eq(SALES_OFFICES.SALES_OFFICE_ID))
                .where(USERS.USER_ID.eq(userId.value))
                // 削除済みかどうかに関わらず、最新のレコードを取得する
                .and(BTT_USERS.valid())
                .orderBy(USERS.VALID_FROM.desc())
                .limit(1)
        }
            .singleOrNull()
            ?: return null

        val rawInsurerReferenceScopeId = user[USERS.INSURER_REFERENCE_SCOPE_ID]
        val rawAgencyId = user[AGENCIES.AGENCY_ID]

        return when {
            // insurerReferenceScopeIdを持つ -> 保険会社ユーザーかつ社員参照範囲設定有り
            rawInsurerReferenceScopeId != null -> {
                val referableScopes = findInsurerReferableScopes(InsurerReferenceScopeId(rawInsurerReferenceScopeId))
                    .map { ReferableScope(it) }
                    .toList()
                UserReferenceScopesDto.Insurer(referableScopes)
            }
            // 代理店IDを持たない -> 保険会社ユーザーかつ最強権限有り
            rawAgencyId == null -> UserReferenceScopesDto.Insurer(null)
            // 代理店IDを持つ -> 代理店または営業所のユーザー
            else -> {
                val agencyId = AgencyId(rawAgencyId)
                val agencyCode = AgencyCode(user.read(AGENCIES.CODE))
                val (salesOfficeId, salesOfficeCode) = user[SALES_OFFICES.SALES_OFFICE_ID]
                    ?.let { SalesOfficeId(it) to SalesOfficeCode(user.read(SALES_OFFICES.CODE)) }
                    ?: (null to null)

                val sharedAlignmentCodes = findSharedAlignmentCodesWithSelf(
                    agencyId,
                    salesOfficeId,
                    SharedAlignmentCode(agencyCode, salesOfficeCode),
                ).toList()

                UserReferenceScopesDto.BelongToAgency(sharedAlignmentCodes)
            }
        }
    }
```