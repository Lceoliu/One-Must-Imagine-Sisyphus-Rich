class_name Feedback
extends RefCounted
## 抢先体验（EA）的反馈入口：主菜单、暂停菜单的"反馈 / 报告问题"，主菜单的"制作人员"，首次启动的 EA 说明。
## 都用现成的 ChoiceScreen 弹窗（标题 + 正文 + 按钮），这里只拼文字、开链接 / 文件夹。
## 联系方式按界面语言分：中文显示微信号（复制），英文显示邮箱（写邮件 / 复制）。2026-11-24 itch 包里定的，2026-11-25 合回主工程。

## 中文界面的微信号
const WECHAT: String = ""
## 英文界面的邮箱
const EMAIL: String = ""
## 制作人员署名：填上后显示在"制作人员"里；空着就不显示这一行
const AUTHOR: String = ""


static func version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


static func logs_dir() -> String:
	return ProjectSettings.globalize_path("user://logs")


## "反馈 / 报告问题"弹窗。on_done(i) 回调：只在点"返回"时调用，调用方关掉弹窗
static func feedback_screen(on_done: Callable) -> ChoiceScreen:
	var cs: ChoiceScreen = ChoiceScreen.create()
	cs.title = Loc.t("feedback.title", "反馈 / 报告问题")
	cs.subtitle = Loc.t("feedback.early_access_v", "抢先体验 v%s") % version()
	cs.dim = 0.92
	var actions: Array[String] = []
	var contact: String = EMAIL if Loc.is_en() else WECHAT
	if Loc.is_en():
		cs.body = Loc.t("feedback.body_email", "邮箱：%s\n卡在哪一晚，或者哪句看不懂，都可以告诉我。\n遇到故障时，请附上版本号和日志文件夹里最新的 godot.log。") % EMAIL
		actions = ["email", "copy", "logs", "back"]
		cs.choices = [{"label": Loc.t("feedback.write_email", "写邮件"), "gold": true}, {"label": Loc.t("feedback.copy_email", "复制邮箱")},
			{"label": Loc.t("feedback.open_logs", "打开日志文件夹")}, {"label": Loc.t("feedback.back", "返回")}]
	else:
		cs.body = Loc.t("feedback.body_wechat", "添加微信：%s\n卡在哪一晚，或者哪句看不懂，都可以告诉我。\n遇到故障时，请附上版本号和日志文件夹里最新的 godot.log。") % WECHAT
		actions = ["copy", "logs", "back"]
		cs.choices = [{"label": Loc.t("feedback.copy_wechat", "复制微信号"), "gold": true}, {"label": Loc.t("feedback.open_logs", "打开日志文件夹")},
			{"label": Loc.t("feedback.back", "返回")}]
	cs.chosen.connect(func(i: int) -> void:
		match actions[i]:
			"email":
				if OS.shell_open("mailto:" + EMAIL) != OK:
					(cs.get_node("%Body") as Label).text = cs.body + Loc.t("feedback.no_mail_app", "\n没有打开邮件程序，可以复制地址。")
			"copy":
				DisplayServer.clipboard_set(contact)
				(cs.get_node("%Buttons").get_child(i) as Button).text = Loc.t("feedback.email_copied", "已复制邮箱") if Loc.is_en() else Loc.t("feedback.wechat_copied", "已复制微信号")
			"logs":
				DirAccess.make_dir_recursive_absolute(logs_dir())
				OS.shell_open(logs_dir())
			"back":
				on_done.call(i)
		)
	return cs


## "制作人员"弹窗：署名、引擎、字体、音效、AI 素材说明；"许可证全文"把 Godot 和字体的许可证写成一个文本文件再打开
static func credits_screen(on_done: Callable) -> ChoiceScreen:
	var cs: ChoiceScreen = ChoiceScreen.create()
	cs.title = Loc.t("feedback.credits", "制作人员")
	cs.subtitle = Loc.t("feedback.credits_sub", "西西弗斯 · 抢先体验 v%s") % version()
	var lines: PackedStringArray = []
	if AUTHOR != "":
		lines.append(Loc.t("feedback.created_by", "制作：") + AUTHOR)
	lines.append(Loc.t("feedback.engine", "引擎：Godot Engine（MIT 许可）"))
	lines.append(Loc.t("feedback.fonts", "字体：Cinzel、GFS Didot、Noto Serif SC（SIL 开源字体许可 1.1）"))
	lines.append(Loc.t("feedback.sound", "音效：程序合成；部分采样来自 CC0 素材——Kenney、rubberduck、qubodup、themightyglider、AntumDeluge、artisticdude、Vinrax、LordTomorrow、Amarikah、Spring Spring（OpenGameArt）"))
	lines.append(Loc.t("feedback.music", "音乐：RandomMind《Medieval: Exploration》《Medieval: King's Feast》、Spring Spring《greek instruments》（CC0）"))
	lines.append(Loc.t("feedback.ai_art", "部分美术素材由 AI 工具辅助生成"))
	cs.body = "\n".join(lines)
	cs.dim = 0.92
	cs.choices = [{"label": Loc.t("feedback.licenses", "许可证全文")}, {"label": Loc.t("feedback.back", "返回"), "gold": true}]
	cs.chosen.connect(func(i: int) -> void:
		if i == 0:
			OS.shell_open(ProjectSettings.globalize_path(write_licenses()))
		on_done.call(i)
		)
	return cs


## 把 Godot 引擎（含第三方组件）和字体的许可证写到 user://licenses.txt，返回路径
static func write_licenses() -> String:
	var path: String = "user://licenses.txt"
	var out: PackedStringArray = [Loc.t("feedback.licenses_head", "Sisyphus v%s — 第三方许可证") % version(), "", "== Godot Engine ==", Engine.get_license_text(), ""]
	var info: Dictionary = Engine.get_license_info()
	for k: Variant in info:
		out.append("== %s ==" % str(k))
		out.append(str(info[k]))
		out.append("")
	var fonts: String = "res://assets/fonts/licenses"
	for f: String in DirAccess.get_files_at(fonts):
		if f.ends_with(".txt"):
			out.append("== %s ==" % f.get_basename())
			out.append(FileAccess.get_file_as_string(fonts + "/" + f))
			out.append("")
	var fa: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if fa != null:
		fa.store_string("\n".join(out))
		fa.close()
	return path


## 首次启动的 EA 说明
static func ea_notice_screen(on_done: Callable) -> ChoiceScreen:
	var cs: ChoiceScreen = ChoiceScreen.create()
	cs.title = Loc.t("feedback.early_access", "抢先体验")
	cs.subtitle = "v%s" % version()
	cs.body = Loc.t("feedback.ea_body", "目前是抢先体验版，数值和文字都还在调整。\n更新之后，存档可能需要重新开始。\n遇到问题或有想法，欢迎从主菜单的「反馈」告诉我们。")
	cs.dim = 0.92
	cs.choices = [{"label": Loc.t("feedback.start_pushing", "开始推石"), "gold": true}]
	cs.chosen.connect(func(i: int) -> void: on_done.call(i))
	return cs
