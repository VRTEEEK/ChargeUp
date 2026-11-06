import Foundation
import ChargeUpCore

/// One line of interface text in both companion languages. Step names,
/// clinical cues, button labels and prompts are not here: they are data in
/// sequence.json.
struct UIText {
    let en: String
    let ar: String

    func `in`(_ language: PromptLanguage) -> String {
        switch language {
        case .en: en
        case .ar: ar
        }
    }

    func `in`(_ language: PromptLanguage, _ args: CVarArg...) -> String {
        String(format: self.in(language), arguments: args)
    }
}

/// The companion's interface text.
enum Copy {
    // Role picker
    static let tagline = UIText(en: "A little light makes a big difference.", ar: "نورٌ صغير يصنع فرقاً كبيراً.")
    static let whoIsThisDevice = UIText(en: "Who is using this device?", ar: "من يستخدم هذا الجهاز؟")
    static let language = UIText(en: "Language", ar: "اللغة")
    static let nurse = UIText(en: "Nurse", ar: "فريق التمريض")
    static let nurseDetail = UIText(en: "Guide the treatment journey.", ar: "قُد رحلة العلاج خطوة بخطوة.")
    static let nurseAction = UIText(en: "Enter Nurse Dashboard", ar: "فتح لوحة التمريض")
    static let parent = UIText(en: "Parent", ar: "الأهل")
    static let parentDetail = UIText(en: "Stay connected to their journey.", ar: "ابقَ قريباً من رحلة طفلك.")
    static let parentAction = UIText(en: "Enter Parent Dashboard", ar: "فتح لوحة الأهل")
    static let haptic = UIText(en: "Haptic", ar: "الاهتزاز")
    static let hapticDetail = UIText(en: "The phone in the child's free hand.", ar: "الهاتف في يد الطفل الحرّة.")
    static let hapticAction = UIText(en: "Start Haptics", ar: "تشغيل الاهتزاز")

    // Top bar and connection
    static let changeRole = UIText(en: "Change role", ar: "تغيير الدور")
    static let linked = UIText(en: "Linked to headset", ar: "متصل بالنظارة")
    static let reconnecting = UIText(en: "Reconnecting, step held", ar: "إعادة الاتصال، الخطوة محفوظة")
    static let lookingForHeadset = UIText(en: "Looking for headset", ar: "البحث عن النظارة")

    // Nurse
    static let treatmentJourney = UIText(en: "Treatment journey", ar: "رحلة العلاج")
    static let currentStage = UIText(en: "Current stage", ar: "المرحلة الحالية")
    static let stageOf = UIText(en: "Stage %d of %d", ar: "المرحلة %d من %d")
    static let gettingReady = UIText(en: "Getting ready", ar: "نستعد")
    static let sessionComplete = UIText(en: "Session complete", ar: "اكتملت الجلسة")
    static let childFeels = UIText(en: "Child feels", ar: "يشعر الطفل")
    static let childSees = UIText(en: "Child sees", ar: "يرى الطفل")
    static let sayToChild = UIText(en: "Say to the child", ar: "قل للطفل")
    static let stageProgress = UIText(en: "Stage progress", ar: "تقدّم المراحل")
    static let lanternCharge = UIText(en: "Lantern charge", ar: "شحن الفانوس")
    static let waitingForHeadset = UIText(en: "Waiting for headset", ar: "بانتظار النظارة")
    static let needleMoment = UIText(en: "Needle moment: sends CONNECT to the headset", ar: "لحظة الإبرة: يرسل CONNECT إلى النظارة")
    static let advancesOnItsOwn = UIText(en: "This step advances on its own", ar: "تتقدّم هذه الخطوة تلقائياً")
    static let startsNewSession = UIText(en: "Clears the headset for the next session", ar: "يهيّئ النظارة للجلسة التالية")
    static let tapStartOnHeadset = UIText(en: "Tap Start on the headset to pair.", ar: "اضغط Start على النظارة للاقتران.")
    static let headset = UIText(en: "Headset", ar: "النظارة")
    static let device = UIText(en: "Device", ar: "الجهاز")
    static let lastMessage = UIText(en: "Last message", ar: "آخر رسالة")
    static let noneYet = UIText(en: "None yet", ar: "لا شيء بعد")
    static let secondsAgo = UIText(en: "%d s ago", ar: "قبل %d ث")
    static let connectRoundTrip = UIText(en: "Connect round trip", ar: "زمن استجابة CONNECT")
    static let readiness = UIText(en: "Readiness", ar: "الجاهزية")
    static let headOnPort = UIText(en: "Head on port", ar: "الرأس نحو المنفذ")
    static let armStill = UIText(en: "Arm still", ar: "الذراع ثابتة")
    static let yes = UIText(en: "Yes", ar: "نعم")
    static let notYet = UIText(en: "Not yet", ar: "ليس بعد")
    static let noSignal = UIText(en: "No signal", ar: "لا إشارة")
    static let session = UIText(en: "Session", ar: "الجلسة")
    static let rehearsal = UIText(en: "Rehearsal", ar: "وضع التدريب")
    static let rehearsalDetail = UIText(en: "Taps every %.0f s so one person can test the headset alone.",
                                        ar: "ينقر كل %.0f ث ليختبر شخص واحد النظارة وحده.")
    static let exportLog = UIText(en: "Export log", ar: "تصدير السجل")
    static let resets = UIText(en: "Resets", ar: "إعادة الضبط")
    static let resetSession = UIText(en: "Reset session", ar: "إعادة ضبط الجلسة")
    static let resetSky = UIText(en: "Reset Sky", ar: "مسح السماء")
    static let resetSkyTitle = UIText(en: "Reset the lantern sky?", ar: "مسح سماء الفوانيس؟")
    static let resetSkyMessage = UIText(
        en: "This clears every lantern the child has collected on the headset, back to the starting lanterns. It cannot be undone.",
        ar: "سيمحو هذا كل الفوانيس التي جمعها الطفل على النظارة ويعيدها إلى فوانيس البداية. لا يمكن التراجع عن ذلك.")
    static let cancel = UIText(en: "Cancel", ar: "إلغاء")
    static let keys = UIText(en: "Keys", ar: "المفاتيح")

    // Timeline
    static let done = UIText(en: "Done", ar: "تمّ")
    static let now = UIText(en: "Now", ar: "الآن")
    static let next = UIText(en: "Next", ar: "التالي")

    // Parent
    static let parentTitle = UIText(en: "Your Little Explorer's Journey", ar: "رحلة مستكشفك الصغير")
    static let parentSubtitle = UIText(en: "Every little light is a moment of courage.", ar: "كل نورٍ صغير هو لحظة شجاعة.")
    static let lanternMirror = UIText(en: "This lantern glows with the one your child is charging.",
                                      ar: "يضيء هذا الفانوس مع الفانوس الذي يشحنه طفلك.")
    static let lanternsCollected = UIText(en: "Lanterns collected", ar: "الفوانيس المجموعة")
    static let awaitingConnection = UIText(en: "Awaiting connection to the headset", ar: "بانتظار الاتصال بالنظارة")
    static let noLanternsYet = UIText(en: "No lanterns yet.", ar: "لا فوانيس بعد.")
    static let journey = UIText(en: "Journey", ar: "الرحلة")
    static let allDone = UIText(en: "All done", ar: "انتهينا")
    static let earlierLanterns = UIText(en: "+ %d earlier", ar: "+ %d أقدم")
}
