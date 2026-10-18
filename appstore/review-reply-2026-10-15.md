# App Review への返信(2026-10-15 / Guideline 2.1 Information Needed)

## A. 「App Reviewに返信」に貼る文面(画面録画の動画を添付)

Hello App Review Team,

Thank you for reviewing Ashiato.

Regarding Guideline 3.1.2: we have added a functional link to the standard Apple Terms of Use (EULA), together with the Privacy Policy link and the subscription details (title, length and price), to the App Description.

Regarding Guideline 2.1 (Information Needed), please find the requested information below. Screen recordings captured on a physical iPhone are attached.

1. Screen recording
Two recordings captured on a physical iPhone 11 are attached. Both begin with launching the app.
- Video 1 (about 3.5 min): the typical user flow: recording a visited place from the calendar (search, companions, date, photo), the map, a trip with its route, the photo album, inviting a partner via iCloud sharing, achievements, and the Privacy Policy.
- Video 2 (about 1 min): the subscription screen ("…" > プレミアム) with the plan, price and free trial, the Terms of Use (Apple standard EULA) and Privacy Policy links, and the purchase flow. The recording was made in the StoreKit sandbox, so the price is shown in USD ($1.99/month); on the Japanese App Store it is ¥300/month.
- Account registration / login / account deletion: not applicable. The app has no accounts and no sign-in. Data is stored in the user's own iCloud (CloudKit private database).
- User-generated content: comments, photos and reactions are visible only to people the user explicitly invites with an iCloud share link (CloudKit sharing). There is no public feed, profile, search for other users or contact with strangers. The owner can remove participants or stop sharing at any time from "…" > 共有の管理 (the standard iCloud sharing screen), and participants can leave.

2. Purpose and target audience
Ashiato is a travel log for couples, families and friends. It solves the problem that travel memories are scattered across camera rolls and chats: places, dates, companions, photos and comments are kept in one shared map that both partners can add to.

3. How to use the main features (no login or sample files required)
- Calendar tab (home): tap a date, search for a place, choose who went, then tap "あしあとを残す" to save.
- To record a trip with several places, tap "旅をまとめて記録" on the calendar and tap the first and last day; then add the places day by day. The route is drawn on a map. Trips are listed in "…" > 旅.
- Map tab: visited prefectures/countries are colored; tap a pin to open the record.
- "…" > アルバム: photos grouped by trip and by place.
- メンバー (bottom bar): add members and their colors. The person icon (top right) creates an iCloud invite link to share the log.
- 実績 (bottom bar): prefecture level, countries and badges.
- Premium: "…" > プレミアム, or tap "add photo" beyond the free limit (3 photos per place).

4. External services
Apple frameworks only: iCloud / CloudKit (storage, sync and sharing), MapKit (maps, place search, reverse geocoding), StoreKit (subscription), PhotosUI (photo picker), EventKit (optional export to the Calendar app), UserNotifications (local notifications). No third-party SDKs, analytics, ads, AI or own servers.

5. Regional differences
The app is distributed in Japan only. All features work the same way in every region.

6. Regulated industry / third-party material
Not applicable.

7. In-App Purchase
One auto-renewable subscription, "Premium Monthly" (¥300/month, 1-week free trial for new subscribers). It unlocks unlimited photos per place (free: 3) and short videos (up to 60 seconds each). If one member subscribes, everyone in the same shared log can use the premium features. To purchase: "…" > プレミアム > "1週間無料で試す". To restore: "購入を復元" on the same screen. To manage or cancel: "…" > プレミアム(加入中) opens the system subscription management screen.

Best regards,
Takahiro Sueoka

## B. App Review に関する情報の「メモ」に追記する文面(短縮版)

No account or login. Data is stored in the user's own iCloud (CloudKit).
Main flow: Calendar tab > tap a date > search a place > choose who went > "あしあとを残す". "旅をまとめて記録" groups several places into a trip.
Sharing: person icon (top right) creates an iCloud invite link. Shared content is visible only to invited people (no public content); "…" > 共有の管理 removes participants or stops sharing.
In-App Purchase: one auto-renewable subscription "Premium Monthly" (¥300/month, 1-week free trial). "…" > プレミアム. Restore on the same screen.
External services: Apple frameworks only (CloudKit, MapKit, StoreKit, PhotosUI, EventKit). No third-party SDKs, analytics or AI.
Distributed in Japan only; works the same in all regions.
