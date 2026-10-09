/// Word lists for the Guide regression check. Chinese and English side by side.
///
/// Sources: `docs/13-glossary.md` (四态, 资料不足, Unknown, 玻璃不确定), `docs/11-compliance-boundaries.md` §2
/// (措辞), `docs/01-product-spec.md` §6 and §11 (待复核, 手工分割), ADR-0010 (禁止).
/// English entries are matched on lowercased text at word boundaries; Chinese entries as substrings.
public enum GuideLexicon {
    /// Never allowed in Guide text (`11` §2: 不用"精确""exact""认证""合格"; 不写"以实测为准").
    public static let forbidden: [String] = [
        "精确", "认证", "合格", "以实测为准",
        "exact", "exactly", "precise", "precisely", "certified",
    ]

    /// Absolute certainty. Allowed only when negated ("不确定", "can't be certain"),
    /// and only checked when the tool result holds something uncertain.
    public static let absoluteCertainty: [String] = [
        "确定", "一定", "肯定", "保证", "必定", "必然", "绝对", "无疑", "确保", "百分之百", "毫无疑问", "放心",
        "definitely", "certainly", "certain", "guaranteed", "guarantee", "for sure", "no doubt",
        "undoubtedly", "surely", "rest assured", "always",
    ]

    /// Claims that state a sun state as known. Checked only in clauses about an uncertain subject,
    /// and allowed there when the same clause carries an uncertainty marker or a negation.
    public static let stateClaims: [String] = [
        "稳定直射", "直射", "有阳光", "阳光充足", "充足的阳光", "阳光充沛", "全天", "整天", "晒得到", "能晒到", "会晒到",
        "晒不到", "照进来", "洒满", "明亮", "很亮", "很暗", "无遮挡", "没有遮挡", "被遮挡", "遮挡", "不受影响", "没有影响",
        "不会影响", "不影响", "已排除", "已处理", "已修正", "不碍事", "没关系",
        "日照充足", "日照不错", "不错的日照", "日照好", "有日照", "没有日照", "采光好", "采光不错", "采光充足", "朝阳",
        "背阴", "阴暗", "阴凉",
        "direct sun", "direct sunlight", "sunlight", "sunny", "full sun", "sun-filled", "sunlit", "bright", "gets sun",
        "get sun", "will get", "receives", "all day", "shaded", "blocked", "no direct sun", "gets no sun", "get no sun", "unaffected",
        "not affected", "won't affect", "doesn't affect", "does not affect", "don't affect", "do not affect",
        "doesn't matter", "don't matter", "not an issue", "no effect", "no impact", "ruled out", "accounted for", "filtered out", "corrected",
    ]

    /// Words that mark a statement as uncertain. Satisfy "未知项必须被提到" and excuse a state claim
    /// in the same clause. Weak hedges ("可能", "may") are left out on purpose: they read as a soft claim.
    public static let uncertaintyMarkers: [String] = [
        "未知", "资料不足", "数据不足", "信息不足", "不确定", "无法确定", "无法判断", "不能确定", "不能判断", "难以判断",
        "待复核", "待确认", "未能", "没能", "不清楚", "不明", "存疑", "未测", "没测到", "无法", "不足以", "看不清", "说不准",
        "unknown", "insufficient", "uncertain", "uncertainty", "not enough", "can't tell", "cannot tell", "can't say",
        "cannot say", "couldn't", "could not", "unclear", "not sure", "unable", "needs review", "pending",
        "not measured", "unmeasured", "unconfirmed", "not confirmed", "inconclusive", "can't confirm", "cannot confirm",
        "no reliable", "not determined", "undetermined",
        // Withholding a result is also a way to flag it (`01` §12: 只显示 R0 与原因，不显示小时数).
        "不给出", "暂不", "不提供", "不显示", "不输出", "not shown", "won't show", "not give", "withheld", "no hours",
        "no sun hours", "no direct-sun hours",
    ]

    /// Negations that cancel a certainty word right after them ("不确定", "无法保证", "can't be certain").
    public static let negationsZh: [String] = ["不", "无", "未", "没", "难", "非", "否"]
    public static let negationsEn: [String] = ["not", "no", "never", "cannot", "can't", "couldn't", "won't", "isn't", "aren't", "without", "nor"]

    /// Words that name the glass subject.
    public static let glass: [String] = ["玻璃", "反射", "反光", "glass", "glazing", "reflection", "reflections", "reflective"]

    /// Words that mark an upper bound ("上界" of `06` §6). An upper bound quoted without one reads as a fact.
    public static let upperBoundMarkers: [String] = [
        "上界", "上限", "至多", "最多", "不超过", "不会超过", "封顶",
        "upper bound", "at most", "up to", "no more than", "maximum", "cap of", "ceiling",
    ]

    /// Words that present a time span as containing a smaller one ("11:15 至 12:40，其中 12:15 至 12:40 对方向敏感").
    public static let inclusion: [String] = ["其中", "包括", "包含", "含", "of which", "including", "within it", "within that"]

    /// Labels that a degraded path requires (`01` §6 分歧写"待复核"; §11 标注"手工分割").
    public static let manualSegmentation: [String] = ["手工分割", "manual segmentation", "manually segmented", "segmented by hand"]
    public static let needsReview: [String] = ["待复核", "needs review", "pending review", "to be reviewed", "needs a review"]
}
