class_name ModalRequest
extends RefCounted
## 模拟需要玩家做选择时发出的请求（取代网页 g.paused + 面板）。sim 在这一拍设置 g.modal，之后暂停推进；
## 表现层（或机器人）读 payload 展示，然后调用 g.answer(i)（i = -1 表示跳过）。

## ALTAR = 祭坛点亮的神降演出（不选，n_choices = 1）；DIALOG 剧情对话；SUMMIT 登顶菜单；NOTICE 通知
enum Kind { ALTAR, DIALOG, SUMMIT, NOTICE }

var kind: Kind = Kind.NOTICE
var id: int = 0
## 纯数据：卡面 {title, sub, cards:[{...}], foot}；对话 {speaker, portrait, pages[], choices[{label, gold}]}
var payload: Dictionary = {}
var n_choices: int = 0
var allow_skip: bool = false
var reroll_left: int = 0
## 表现层至少展示多久（秒）；sim 不等它，机器人不看它
var min_show: float = 0.0
## 回答回调：Callable(i: int)；由发出请求的系统设置
var on_answer: Callable = Callable()
var on_reroll: Callable = Callable()
