# عدّاء السودان · Sudan Runner (Gadaman)

لعبة **جري لا نهائي ثلاثية الأبعاد** لشوارع الخرطوم، مبنية بـ **Godot 4.4** ومهندسة لتعمل بسلاسة على هواتف أندرويد الضعيفة (2 GB RAM) والهواتف القوية (120 Hz) على حد سواء.
3D endless runner set in Khartoum, built with Godot 4.4 and tuned for Android — from 2 GB budget phones to 120 Hz flagships.

[![Build APK](https://github.com/azmifatahi/gadaman/actions/workflows/build.yml/badge.svg)](https://github.com/azmifatahi/gadaman/actions/workflows/build.yml)

![القائمة الرئيسية](assets/art/menu_bg.png)

## 📸 من داخل اللعبة / Screenshots

| اللعب / Gameplay | القفز / Jump |
| --- | --- |
| ![gameplay](docs/screenshots/shot_03_gameplay.png) | ![jump](docs/screenshots/shot_04_jump.png) |

| القائمة / Menu | الإعدادات / Settings | نهاية الجولة / Game over |
| --- | --- | --- |
| ![menu](docs/screenshots/shot_01_menu.png) | ![settings](docs/screenshots/shot_08_settings.png) | ![gameover](docs/screenshots/shot_07_gameover.png) |

| الانحناء / Slide | طريقة اللعب / How to play | إيقاف مؤقت / Pause |
| --- | --- | --- |
| ![slide](docs/screenshots/shot_05_slide.png) | ![howto](docs/screenshots/shot_02_howto.png) | ![pause](docs/screenshots/shot_06_pause.png) |

> هذه الصور مُلتقطة آليًا من بناء الـ CI نفسه (`godot --screenshot` مع مُصيّر برمجي) — أي أنها تعكس ما ستراه على الجهاز تمامًا.
> Captured automatically by CI from the real build on a software GL renderer.

---

## 1. ما داخل اللعبة / What is in the box

| العنصر | التفاصيل |
| --- | --- |
| المحرك | Godot **4.4.x** — GDScript فقط (لا C#، لا مكتبات خارجية) |
| المُصيّر | **GL Compatibility** (يعمل على أي GPU أندرويد تقريبًا + إقلاع أسرع + ذاكرة أقل) |
| الحجم | المشروع كامل ≈ 3 MB (كل الـ 3D مُولّد برمجيًا، لا نماذج مستوردة) |
| اللغة | العربية افتراضيًا + الإنجليزية (زر تبديل داخل الإعدادات، مع دعم RTL) |
| اللعب | جري تلقائي، 3 حارات، قفز، انحناء، جمع أكواب الكركديه والعرديب والقونقليز |
| الأداء | مدير أداء يفحص RAM/CPU/GPU/معدل تحديث الشاشة ويضبط الجودة تلقائيًا + دقة ديناميكية |

**الميزات:**

- 🏃 **شخصية مغلّفة بعلم السودان** (أحمر/أبيض/أسود + مثلث أخضر) مع عباءة علم ترفرف أثناء الجري.
- 🏙️ **توليد إجرائي لشوارع الخرطوم**: أسواق شعبية، كورنيش النيل، حواري طينية، جسر النيل الأزرق — 5 أنماط مشاهد تتناوب.
- 🎬 **حركة أكشن سينمائية**: تبديل حارات بالسرعة، ميلان كاميرا، FOV ديناميكي، تحطيم الصناديق عند السرعة القصوى، وتعثر مع استعادة التوازن بدل النهاية الفورية.
- 🚚 **نظام توصيل مرحلي**: API لمهمات توصيل العرديب/الكركديه/القونقليز لمسافة محددة قبل انتهاء الوقت بجانب الوضع اللانهائي.
- 🚌 **عوائق محلية**: حواجز الطرق، الحفر، عربات الكرو، الأمجد الواقفة، طاولات الباعة، صناديق السوق، وحواجز منخفضة للانحناء.
- 🥤 **مجموعات محلية**: أكواب الكركديه، العرديب، والقونقليز (مع نظام كومبو ×5).
- 🎵 **موسيقى ومؤثرات مولّدة برمجيًا** (إيقاع سوداني: دوم/تك/شيكر + خط لحن خماسي) — لا حقوق محفوظة.
- 📱 **تحكم مناسب للجوال**: سحب بالإصبع (يمين/يسار/أعلى/أسفل) + تحكم بالإمالة (اختياري) + لوحة مفاتيح للاختبار.
- ⚡ **بدون فيزياء وبدون GC أثناء اللعب**: تصادم حسابي، تجميع كائنات (pooling) لكل شيء، دقة ديناميكية.

---

## 2. طريقة التشغيل / Quick start

```bash
git clone https://github.com/azmifatahi/gadaman.git
cd gadaman
godot --editor      # أو افتح المشروع من مدير مشاريع Godot
```

ثم اضغط **F5**. (المطلوب: Godot 4.4 أو أحدث، بدون أي إضافات.)

على الجوال: شغّل اللعبة من Godot عبر **Remote Debug → Run on Android device**، أو حمّل APK جاهزًا من تبويب **Actions** في المستودع.

### التحكم / Controls

| الحركة | اللمس | لوحة المفاتيح |
| --- | --- | --- |
| تغيير الحارة | سحب يمين/يسار | ← → أو A/D |
| قفز | سحب لأعلى | ↑ / W / مسافة |
| انحناء | سحب لأسفل | ↓ / S |
| إمالة (اختياري) | إمالة الجهاز يمينًا/يسارًا | — |
| إيقاف مؤقت | زر الإيقاف | Esc |

---

## 3. البنية المعمارية / Architecture

```
gadaman/
├── project.godot                 # إعدادات المحرك + المدخلات + Autoloads
├── export_presets.cfg            # إعدادات تصدير APK (أيقونات العلم، اسم الحزمة)
├── scenes/main.tscn              # المشهد الوحيد: World + Player + Track + Camera + FX + UI
├── scripts/
│   ├── core/
│   │   ├── settings.gd           # حفظ الإعدادات (ConfigFile) + الاهتزاز
│   │   ├── localization.gd       # نصوص عربي/إنجليزي + RTL
│   │   ├── performance_manager.gd# كشف فئة الجهاز + دقة ديناميكية
│   │   ├── audio_manager.gd      # مشغّل صوت مجمّع (pool) بدون تخصيص أثناء اللعب
│   │   └── game_manager.gd       # حالة الجولة، النقاط، الكومبو، أفضل نتيجة
│   ├── player/
│   │   ├── player_controller.gd  # الحارات، القفز، الانحناء، السحب/الإمالة
│   │   └── runner_model.gd       # نموذج الشخصية (علم السودان) وتحريكه الإجرائي
│   ├── world/
│   │   ├── world.gd              # المنسّق: الإضاءة، الربط، دورة حياة الجولة
│   │   ├── track_manager.gd      # توليد المسار + تجميع العوائق + التصادم
│   │   ├── track_segment.gd      # مقطع شارع (pooled)
│   │   ├── track_prop.gd         # عائق (pooled)
│   │   ├── collectible.gd        # كوب قابل للجمع (pooled)
│   │   ├── segment_builder.gd    # توليد هندسة الشارع إجرائيًا (5 أنماط)
│   │   ├── prop_library.gd       # كتالوج العوائق والأكواب + بيانات اللعب
│   │   ├── mesh_kit.gd           # أدوات بناء هندسة (صندوق/أسطوانة/علم...)
│   │   ├── camera_rig.gd         # كاميرا مطاردة + اهتزاز + FOV متغير
│   │   └── fx.gd                 # جزيئات مجمّعة (غبار/لمعان/احتفال)
│   └── ui/
│       ├── ui_theme.gd           # ثيم الواجهة بالكود (خط Cairo، ألوان العلم)
│       └── ui_root.gd            # HUD + القوائم + الإعدادات + طريقة اللعب
├── assets/
│   ├── art/       (أيقونة العلم، خلفية القائمة، الشعار، أكواب HUD)
│   ├── textures/  (أسفلت، رمل، علم، ظل، دخان)
│   ├── audio/     (موسيقى + 9 مؤثرات OGG)
│   └── fonts/     (Cairo — SIL OFL)
├── tools/
│   ├── generate_assets.py        # يعيد توليد كل الصور (Pillow)
│   ├── generate_audio.py         # يعيد توليد الموسيقى والمؤثرات (numpy + ffmpeg)
│   └── ci_configure_android.py   # يضبط مسارات Android SDK في CI
└── .github/workflows/build.yml   # فحص + اختبار headless + تصدير APK
```

### تدفّق اللعبة / Game flow

```
UI (زر ابدأ) ──play_requested──▶ World ──▶ Game.start_run() + Track.start_run() + Player.start_running()
Track._process:  يحرّك العالم ◀ التصادم/الجمع ◀ Game.add_distance / collect_cup / end_run
Game.state_changed ──▶ UI (HUD ⇄ Pause ⇄ Game Over)
Track.prop_hit ──▶ World: Player.die() + Camera.shake() + FX.crash() + Toast
```

اللاعب **لا يتحرك للأمام**؛ الشارع هو الذي يتحرك نحوه. كل العوائق والأكواب تُعاد إلى مخزنها (pool) بعد تجاوزها، لذلك لا يوجد تخصيص ذاكرة أثناء الجري.

### النقاط / Scoring

| المصدر | القيمة |
| --- | --- |
| المسافة | +1 نقطة لكل متر |
| الكوب | 10 × المضاعف (1 → 5) |
| الكومبو | كل 5 أكواب متتالية (خلال 2.2 ثانية) ترفع المضاعف |
| الإنجاز | كل 250 متر: مؤثر صوتي + اهتزاز + احتفال بصري |

---

## 4. إدارة الأداء / Performance manager

`scripts/core/performance_manager.gd` يقرأ: ذاكرة RAM (`OS.get_memory_info`)، عدد الأنوية، اسم GPU (`RenderingServer.get_video_adapter_name`)، معدل تحديث الشاشة، الدقة و DPI — ثم يصنّف الجهاز:

| | **منخفض** (2–4 GB) | **متوسط** (4–6 GB) | **عالي** (8 GB+) |
| --- | --- | --- | --- |
| الظلال | مُطفأة + ظل بسيط تحت الشخصية | ظل باتجاهي 32 م | ظل 70 م + أطلس 2048 |
| الدقة الداخلية | 0.78× | 0.92× | 1.0× |
| MSAA | معطّل | معطّل | 2× |
| الضباب | ضباب كثيف (118 م) | 195 م | 250 م |
| كثافة الزينة | 55% | 100% | 135% |
| الجزيئات | 45% | 80% | 100% |
| سقف FPS | 30 | 60 | معدل الشاشة (حتى 120) |
| التظليل | per-vertex | per-pixel | per-pixel + تعديل ألوان |

- **Auto**: يُطبّق الفئة المكتشفة. اللاعب يستطيع تجاوزها من الإعدادات (Auto/Low/Medium/High) — يُحفظ الاختيار.
- **دقة ديناميكية**: إذا نزل FPS عن 82% من الهدف مرتين متتاليتين تُخفّض الدقة 0.08 حتى حد 0.55، وتعود تدريجيًا عند توفر فائض. مُعطّلة عند اختيار جودة يدوية.
- **سقف FPS** = `Engine.max_fps`، ويُقصّ إلى معدل تحديث الشاشة لتوفير البطارية.

لماذا **Compatibility** بدل Mobile/Vulkan؟ لأنه الوحيد الذي يضمن التشغيل من Android 7 على GPUs قديمة بدون تعطّل، وأقل استهلاكًا للذاكرة — وهو أهم من فروق الإضاءة في لعبة أركيد سريعة.

---

## 5. الثيم السوداني / The Sudanese layer

- **العلم**: مرسوم بدقة عبر `MeshKit.add_flag_panel` (ثلاثة أشرطة + مثلث أخضر بنسبة 1:2 الصحيحة)، ويظهر على: بدلة العدّاء، عباءته، لافتات الشوارع، حافلات الأمجد، وحواجز الانحناء.
- **البيئة**: مآذن وقباب، أكاسيا مسطحة التاج، نخيل الكورنيش، بيوت طين ببوابات ملوّنة، أطنان الماء على الأسطح، حبال غسيل، لمبات معلّقة في السوق، عربات الكرو، والأمجد.
- **الأكواب**: كركديه (أحمر)، عرديب (عنبري)، قونقليز (كريمي) — كلها تعمل كعملات لجمع النقاط.
- **الصوت**: دوم/تك/كلاب/شيكر + باص + لحن خماسي (D مينور) بمقاربة كرابلس-سترونغ، كله مُولّد بـ`numpy` ثم OGG.

إعادة التوليد بعد أي تعديل:

```bash
pip install pillow numpy
python3 tools/generate_assets.py          # كل الصور والأيقونات
FFMPEG_BIN=$(which ffmpeg) python3 tools/generate_audio.py   # الموسيقى والمؤثرات
```

---

## 6. بناء APK / Building the APK

### أ) عبر GitHub Actions (الأسهل — لا تحتاج تثبيت أي شيء)

كل `push` إلى `main` أو أي فرع `arena/**` (أو Pull Request) يشغّل:

1. **Validate** — فحص GDScript + استيراد المشروع + **اختبار لعب headless** (يبدأ جولة، يقفز، ينحني، يغيّر الحارات، ينهي الجولة، ويطبع `SMOKE_OK`).
2. **Export APK** — يثبّت Android SDK (build-tools 34/35) ويصدّر APK موقّعًا بمفتاح التصحيح.

للتحميل مباشرة (بدون تسجيل دخول):
**[⬇️ أحدث APK (v1.1.0)](../../releases/latest/download/sudan-runner.apk)** — من صفحة الإصدار `latest-build`، أو من **Actions → آخر تشغيل → Artifacts → `sudan-runner-apk`**.
ولإنشاء إصدار رسمي: أنشئ وسمًا مثل `v1.1.0`:

```bash
git tag v1.1.0 && git push origin v1.1.0
```

سيُرفق الـ APK تلقائيًا بصفحة **Releases**.

> ⚠ **ملاحظة الترقية من v1.0.0 إلى v1.1.0**: تم تبديل شهادة توقيع الـ APK في CI إلى شهادة ثابتة (تُحفَظ في `actions/cache`) حتى تتثبّت التحديثات المستقبلية فوق القديمة بدون حذف. للانتقال من 1.0.0 القديم إلى 1.1.0: احذف النسخة القديمة من إعدادات الهاتف أولاً، ثم ثبّت 1.1.0 (نتائجك المحفوظة لن تفقد لأن `retain_data_on_uninstall=true` مُفَعّل من 1.1.0 فما فوق). من 1.1.0 فصاعدًا، ستعمل التحديثات الهوائية مباشرة.

### ب) محليًا

```bash
# 1) ثبّت قوالب التصدير: Editor → Manage Export Templates → Download and Install
# 2) ثبّت Android SDK + JDK 17، ثم في Godot:
#    Editor → Editor Settings → Export → Android → android_sdk_path / java_sdk_path
mkdir -p build
godot --headless --import
godot --headless --export-debug   "Android" build/sudan-runner-debug.apk
# إصدار مُوقّع للنشر:
godot --headless --export-release "Android" build/sudan-runner.apk
```

### ج) تصدير إصدار موقّع بمفتاحك (Play Store)

```bash
keytool -genkeypair -v -keystore release.keystore -alias sudanrunner \
  -keyalg RSA -keysize 2048 -validity 10000
# ثم أدخل المسار وكلمة المرور في:
# Project → Export → Android → Keystore (release)
```

---

## 7. التخصيص السريع / Tuning cheatsheet

| ما تريده | المكان |
| --- | --- |
| صعوبة أسرع/أبطأ | `track_manager.gd`: `BASE_SPEED`, `MAX_SPEED`, `SPEED_PER_METER` |
| مسافة رد الفعل | `track_manager.gd`: `gap = clampf(speed * 0.62, 9.5, 20.0)` |
| ارتفاع القفز | `player_controller.gd`: `JUMP_VELOCITY` و `GRAVITY` |
| مدة الانحناء | `player_controller.gd`: `SLIDE_TIME` |
| أداء الجوال الضعيف | `performance_manager.gd`: كتلة `Tier.LOW` |
| ألوان البيئة | `segment_builder.gd`: قاموس `PALETTE` |
| سرعة التوليد البصري | `track_manager.gd`: `_spawn_row()` |
| النصوص العربية | `scripts/core/localization.gd` |

---

## 8. الاختبار / Testing

```bash
# اختبار لعب كامل بلا شاشة (يُستخدم في CI)
godot --headless --quit-after 1200 -- --smoke

# فحص صياغة كل السكربتات
pip install "gdtoolkit>=4,<5" && for f in $(find scripts -name '*.gd'); do gdparse "$f"; done
```

---

## 9. الترخيص والشكر / License & credits

- الكود: MIT.
- خط **Cairo** — SIL Open Font License 1.1 (`assets/fonts/OFL.txt`).
- كل الصور والأصوات في هذا المستودع **مولّدة برمجيًا** بواسطة سكربتات `tools/`، ولا تحتوي على أي أصول محفوظة الحقوق.
- مستوحاة من كلاسيكيات الجري اللانهائي، لكن كل المحتوى سوداني أصلي.

صنع بـ ❤️ لمشروع **gadaman**.

### ترقية الرسومات الواقعية / Semi-realistic art upgrade

راجع [`docs/ASSET_IMPORT_GUIDE.md`](docs/ASSET_IMPORT_GUIDE.md) لخطوات Mixamo/GLB
والـAnimationTree وتراخيص Poly Pizza/Sketchfab. يمكن تشغيل
`scripts/tools/SetupRealisticRunner.gd` من محرر Godot بعد تحديد نموذج البطل لتطبيق
بدلة السودان المعدنية وReflectionProbe تلقائياً.
