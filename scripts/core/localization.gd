## Tiny two-language dictionary (Arabic + English).
##
## The game ships both languages in one 4 KB script instead of full Godot
## translation resources: fewer imports, faster cold start on budget phones and
## the UI can retranslate itself in one frame (see ui/hud.gd::retranslate).
extends Node

const STRINGS := {
	"ar": {
		"game.title": "عدَّاء السودان",
		"game.subtitle": "شوارع الخرطوم",
		"menu.play": "ابدأ الجري",
		"menu.settings": "الإعدادات",
		"menu.howto": "طريقة اللعب",
		"menu.best": "أفضل نتيجة",
		"menu.quit": "خروج",
		"hud.score": "النقاط",
		"hud.distance": "المسافة",
		"hud.cups": "الكؤوس",
		"hud.combo": "سلسلة",
		"hud.pause": "إيقاف مؤقت",
		"hud.meters": "م",
		"state.paused": "إيقاف مؤقت",
		"state.resume": "متابعة",
		"state.restart": "من جديد",
		"state.menu": "القائمة",
		"state.gameover": "انتهت الجولة",
		"state.newbest": "رقم قياسي جديد!",
		"state.score": "النقاط",
		"state.distance": "المسافة",
		"state.cups": "الكؤوس المجمّعة",
		"settings.title": "الإعدادات",
		"settings.graphics": "الرسوميات",
		"settings.auto": "تلقائي",
		"settings.low": "منخفض",
		"settings.medium": "متوسط",
		"settings.high": "عالي",
		"settings.fps": "معدل الإطارات",
		"settings.fps_auto": "تلقائي",
		"settings.tilt": "التحكم بالإمالة",
		"settings.haptics": "الاهتزاز",
		"settings.music": "الموسيقى",
		"settings.sfx": "المؤثرات",
		"settings.language": "اللغة",
		"settings.tier": "فئة الجهاز",
		"settings.tier_low": "منخفض",
		"settings.tier_medium": "متوسط",
		"settings.tier_high": "عالي",
		"settings.back": "رجوع",
		"settings.reset": "إعادة ضبط",
		"howto.title": "طريقة اللعب",
		"howto.swipe": "اسحب يميناً أو يساراً لتغيير الحارة",
		"howto.up": "اسحب لأعلى للقفز",
		"howto.down": "اسحب لأسفل للانحناء",
		"howto.collect": "اجمع أكواب الكركديه والعرديب",
		"howto.start": "فهمت، هيا بنا!",
		"toast.combo": "سلسلة ×%d",
		"toast.milestone": "%d متر!",
		"toast.crash": "أوه!",
		"crash.barrier": "حاجز طريق",
		"crash.cart": "عربة كرو",
		"crash.bus": "أمجد واقف",
		"crash.table": "طاولة بائع",
		"crash.crates": "صناديق السوق",
		"crash.pothole": "حفرة",
		"crash.bar": "حاجز منخفض",
		"hint.swipe": "اسحب للبدء",
	},
	"en": {
		"game.title": "SUDAN RUNNER",
		"game.subtitle": "Khartoum Streets",
		"menu.play": "START RUN",
		"menu.settings": "SETTINGS",
		"menu.howto": "HOW TO PLAY",
		"menu.best": "BEST",
		"menu.quit": "QUIT",
		"hud.score": "SCORE",
		"hud.distance": "DISTANCE",
		"hud.cups": "CUPS",
		"hud.combo": "COMBO",
		"hud.pause": "PAUSE",
		"hud.meters": "m",
		"state.paused": "PAUSED",
		"state.resume": "RESUME",
		"state.restart": "RUN AGAIN",
		"state.menu": "MENU",
		"state.gameover": "RUN OVER",
		"state.newbest": "NEW BEST!",
		"state.score": "SCORE",
		"state.distance": "DISTANCE",
		"state.cups": "CUPS COLLECTED",
		"settings.title": "SETTINGS",
		"settings.graphics": "GRAPHICS",
		"settings.auto": "AUTO",
		"settings.low": "LOW",
		"settings.medium": "MEDIUM",
		"settings.high": "HIGH",
		"settings.fps": "FRAME RATE",
		"settings.fps_auto": "AUTO",
		"settings.tilt": "TILT CONTROLS",
		"settings.haptics": "HAPTICS",
		"settings.music": "MUSIC",
		"settings.sfx": "SOUND FX",
		"settings.language": "LANGUAGE",
		"settings.tier": "DEVICE TIER",
		"settings.tier_low": "LOW",
		"settings.tier_medium": "MEDIUM",
		"settings.tier_high": "HIGH",
		"settings.back": "BACK",
		"settings.reset": "RESET",
		"howto.title": "HOW TO PLAY",
		"howto.swipe": "Swipe left / right to change lane",
		"howto.up": "Swipe up to jump",
		"howto.down": "Swipe down to slide",
		"howto.collect": "Collect karkadeh & aradaib cups",
		"howto.start": "GOT IT, LET'S RUN!",
		"toast.combo": "COMBO ×%d",
		"toast.milestone": "%d m!",
		"toast.crash": "Ouch!",
		"crash.barrier": "Road barrier",
		"crash.cart": "Karu cart",
		"crash.bus": "Parked amjad",
		"crash.table": "Vendor table",
		"crash.crates": "Market crates",
		"crash.pothole": "Pothole",
		"crash.bar": "Low barrier",
		"hint.swipe": "Swipe to start",
	},
}


func current_language() -> String:
	if has_node("/root/Settings"):
		return get_node("/root/Settings").language
	return "ar"


func is_rtl() -> bool:
	return current_language() == "ar"


func t(key: String) -> String:
	var lang := current_language()
	var table: Dictionary = STRINGS.get(lang, STRINGS["en"])
	if table.has(key):
		return table[key]
	var fallback: Dictionary = STRINGS["en"]
	return fallback.get(key, key)


func tf(key: String, args: Array) -> String:
	return t(key) % args
