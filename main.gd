extends Node2D

const PLAYER_NAMES := ["あなた", "Luca", "Don", "Tomaso", "Mina"]
const START_HAND_SIZE := 3
const MIN_PLAYERS := 3
const MAX_PLAYERS := 5
const CARD_W := 90.0
const CARD_H := 128.0
const TABLE_BG_PATH := "res://assets/ui/emblem-market-table-background.png"
const CARD_BACK_PATH := "res://assets/ui/emblem-market-card-back.png"

var test_mode := false
var elapsed := 0.0
var done := false
var last_test_inputs: Dictionary = {}
var custom_metrics: Dictionary = {}

var rng := RandomNumberGenerator.new()
var player_count := 4
var players: Array = []
var deck: Array = []
var discard: Array = []
var current_player := 0
var starting_player := 0
var turn_number := 0
var phase := "setup"
var prompt := ""
var selected_rank4_color := "red"
var pending_attack: Dictionary = {}
var pending_targets: Array = []
var pending_target_index := 0
var selected_jacks := 0
var winner := -1
var eliminated_this_turn: Array = []
var action_locked := false

var root_ui: Control
var setup_panel: Control
var game_panel: Control
var hand_area: Control
var action_row: HBoxContainer
var player_row: HBoxContainer
var log_box: RichTextLabel
var prompt_label: Label
var deck_pile_label: Label
var discard_pile_label: Label
var phase_label: Label
var table_texture: Texture2D
var card_back_texture: Texture2D


func _ready() -> void:
	rng.randomize()
	table_texture = load(TABLE_BG_PATH) as Texture2D
	card_back_texture = load(CARD_BACK_PATH) as Texture2D
	_build_ui()
	_sync_ui_to_viewport()
	get_viewport().size_changed.connect(_sync_ui_to_viewport)
	_reset_game(false)


func _physics_process(delta: float) -> void:
	elapsed += delta
	if test_mode:
		return
	if phase == "ai_thinking":
		_ai_step()


func _reset_game(start_immediately := false) -> void:
	elapsed = 0.0
	done = false
	winner = -1
	turn_number = 0
	current_player = 0
	starting_player = 0
	players.clear()
	deck.clear()
	discard.clear()
	pending_attack.clear()
	pending_targets.clear()
	pending_target_index = 0
	selected_jacks = 0
	eliminated_this_turn.clear()
	action_locked = false
	phase = "setup"
	prompt = "プレイヤー数を選んで開始してください。"
	custom_metrics = {}

	if start_immediately:
		_start_match(player_count)
	else:
		_show_setup()
		_refresh()


func _start_match(count: int) -> void:
	player_count = clampi(count, MIN_PLAYERS, MAX_PLAYERS)
	players.clear()
	deck = _build_deck()
	_shuffle(deck)
	discard.clear()
	for i in range(player_count):
		players.append({
			"name": PLAYER_NAMES[i],
			"hand": [],
			"alive": true,
			"ai": i != 0,
		})
	for _r in range(START_HAND_SIZE):
		for p in range(player_count):
			_draw_to(p)
	starting_player = rng.randi_range(0, player_count - 1)
	current_player = starting_player
	turn_number = 1
	phase = "turn_start"
	prompt = ""
	_log("ゲーム開始。開始プレイヤーは %s。" % _player_name(current_player))
	_show_game()
	_begin_turn()


func _begin_turn() -> void:
	if done:
		return
	current_player = _next_alive_from(current_player)
	var p := _player(current_player)
	if p.is_empty():
		return
	phase = "draw"
	var drawn := _draw_to(current_player)
	if drawn:
		_log("%s が山札から1枚引いた。" % _player_name(current_player))
	else:
		_log("%s のドロー。山札は空。" % _player_name(current_player))
	phase = "discard"
	if p["ai"]:
		prompt = "%s のターン。" % _player_name(current_player)
		phase = "ai_thinking"
	else:
		prompt = "手札から必ず1枚捨ててください。"
	_refresh()


func _human_discard(index: int) -> void:
	if phase != "discard" or current_player != 0 or action_locked:
		return
	if index < 0 or index >= _hand(0).size():
		return
	var card := _remove_card(0, index)
	_discard_card(card)
	_log("あなたは %s を捨てた。" % _card_text(card))
	_resolve_active_discard(0, card)


func _ai_step() -> void:
	if action_locked or done:
		return
	action_locked = true
	await get_tree().create_timer(0.35).timeout
	action_locked = false
	if phase != "ai_thinking" or done:
		return
	var idx := _choose_ai_discard(current_player)
	var card := _remove_card(current_player, idx)
	_discard_card(card)
	_log("%s が %s を捨てた。" % [_player_name(current_player), _card_text(card)])
	_resolve_active_discard(current_player, card)


func _resolve_active_discard(actor: int, card: Dictionary) -> void:
	if done:
		return
	var rank: int = int(card["rank"])
	if rank in [1, 2, 3, 7, 10]:
		_start_attack(actor, rank)
	elif rank == 4:
		_start_four(actor)
	elif rank == 8:
		if _draw_to(actor):
			_log("%s は 8 の効果で1枚引いた。" % _player_name(actor))
		else:
			_log("8 の効果。山札は空。")
		_end_turn()
	elif rank == 11:
		_log("11 は攻撃強化用。単独で捨てても効果なし。")
		_end_turn()
	elif rank == 53:
		_start_joker(actor)
	else:
		_end_turn()


func _start_attack(actor: int, rank: int) -> void:
	selected_jacks = 0
	pending_attack = {
		"actor": actor,
		"rank": rank,
		"base": _base_attack_amount(rank),
		"amount": _base_attack_amount(rank),
		"steal": rank == 7,
	}
	if _has_rank(actor, 11):
		if actor == 0:
			phase = "jack_boost"
			prompt = "攻撃前に 11 を重ねると効果値が +1 されます。"
			_refresh()
		else:
			while _has_rank(actor, 11) and rng.randf() < 0.45:
				_use_jack(actor)
			_choose_attack_targets()
	else:
		_choose_attack_targets()


func _human_use_jack() -> void:
	if phase != "jack_boost":
		return
	if _use_jack(0):
		selected_jacks += 1
		prompt = "11 を %d枚使用中。さらに重ねるか対象選択へ進んでください。" % selected_jacks
	_refresh()


func _human_finish_jacks() -> void:
	if phase == "jack_boost":
		_choose_attack_targets()


func _use_jack(player_index: int) -> bool:
	var idx := _find_rank(player_index, 11)
	if idx < 0:
		return false
	var jack := _remove_card(player_index, idx)
	_discard_card(jack)
	pending_attack["amount"] = int(pending_attack["amount"]) + 1
	_log("%s が 11 を重ね、効果値 +1。" % _player_name(player_index))
	return true


func _choose_attack_targets() -> void:
	var actor: int = int(pending_attack["actor"])
	var rank: int = int(pending_attack["rank"])
	if rank == 3:
		pending_targets = []
		for i in range(players.size()):
			if i != actor and _is_alive(i):
				pending_targets.append(i)
		pending_target_index = 0
		_resolve_next_group_target()
		return
	if actor == 0:
		phase = "choose_target"
		prompt = "攻撃対象を選んでください。"
		_refresh()
	else:
		var candidates := _alive_opponents(actor)
		if candidates.is_empty():
			_end_turn()
			return
		_attack_single_target(actor, candidates[rng.randi_range(0, candidates.size() - 1)])


func _human_choose_target(target: int) -> void:
	if phase != "choose_target":
		return
	_attack_single_target(0, target)


func _attack_single_target(source: int, target: int) -> void:
	pending_attack["source"] = source
	pending_attack["target"] = target
	pending_attack["cancelled"] = false
	_log("%s が %s を対象にした。" % [_player_name(source), _player_name(target)])
	_offer_defense(source, target)


func _offer_defense(source: int, target: int) -> void:
	if not _is_alive(target):
		_end_turn()
		return
	if _hand(target).is_empty():
		_apply_attack(source, target)
		return
	if _has_rank(target, 6) or _has_rank(target, 5):
		if target == 0:
			phase = "defense"
			prompt = "%s から攻撃されています。5で反転、6で無効化できます。" % _player_name(source)
			_refresh()
		else:
			if _has_rank(target, 6) and rng.randf() < 0.62:
				_human_or_ai_defend(target, 6)
			elif _has_rank(target, 5) and rng.randf() < 0.52:
				_human_or_ai_defend(target, 5)
			else:
				_apply_attack(source, target)
	else:
		_apply_attack(source, target)


func _human_defense(rank: int) -> void:
	if phase != "defense":
		return
	if rank == 0:
		_apply_attack(int(pending_attack["source"]), int(pending_attack["target"]))
		return
	_human_or_ai_defend(0, rank)


func _human_or_ai_defend(player_index: int, rank: int) -> void:
	var idx := _find_rank(player_index, rank)
	if idx < 0:
		_apply_attack(int(pending_attack["source"]), int(pending_attack["target"]))
		return
	var card := _remove_card(player_index, idx)
	_discard_card(card)
	if rank == 6:
		_log("%s が 6 で攻撃を無効化した。" % _player_name(player_index))
		_after_single_attack()
	elif rank == 5:
		var old_source: int = int(pending_attack["source"])
		var old_target: int = int(pending_attack["target"])
		_log("%s が 5 で攻撃を反転した。" % _player_name(player_index))
		pending_attack["source"] = old_target
		pending_attack["target"] = old_source
		_offer_defense(old_target, old_source)


func _apply_attack(source: int, target: int) -> void:
	var rank: int = int(pending_attack["rank"])
	var amount: int = int(pending_attack["amount"])
	if rank == 3:
		_apply_rank3_to_target(source, target, amount)
	elif rank == 7:
		_apply_positional_transfer(source, target, amount)
	else:
		_apply_positional_discard(source, target, amount)
	_after_single_attack()


func _apply_positional_discard(source: int, target: int, amount: int) -> void:
	var count := mini(amount, _hand(target).size())
	if count <= 0:
		_log("%s の手札は空。攻撃は空振り。" % _player_name(target))
		return
	if source == 0 and not _player(target)["ai"]:
		return
	var positions := _pick_positions(_hand(target).size(), count)
	for pos in positions:
		var removed := _remove_card(target, pos)
		_discard_card(removed)
		_log("%s の伏せ札 %d 枚目が捨て札へ。" % [_player_name(target), pos + 1])
		_trigger_nine_if_needed(target, removed)


func _apply_positional_transfer(source: int, target: int, amount: int) -> void:
	var count := mini(amount, _hand(target).size())
	if count <= 0:
		_log("%s の手札は空。7 は空振り。" % _player_name(target))
		return
	var positions := _pick_positions(_hand(target).size(), count)
	for pos in positions:
		var removed := _remove_card(target, pos)
		_hand(source).append(removed)
		_log("%s が %s の伏せ札 %d 枚目を奪った。" % [_player_name(source), _player_name(target), pos + 1])


func _apply_rank3_to_target(source: int, target: int, amount: int) -> void:
	var count := mini(amount, _hand(target).size())
	if count <= 0:
		_log("%s の手札は空。3 の効果なし。" % _player_name(target))
		return
	for _i in range(count):
		if target == 0:
			phase = "rank3_choose"
			prompt = "3 の攻撃を受けています。捨てるカードを選んでください。残り %d 枚。" % (count - _i)
			pending_attack["rank3_remaining"] = count - _i
			pending_attack["rank3_source"] = source
			pending_attack["rank3_target"] = target
			_refresh()
			return
		var idx := _choose_ai_discard(target)
		var removed := _remove_card(target, idx)
		_discard_card(removed)
		_log("%s が 3 の効果で %s を捨てた。" % [_player_name(target), _card_text(removed)])
		_trigger_nine_if_needed(target, removed)
	_after_single_attack()


func _human_rank3_discard(index: int) -> void:
	if phase != "rank3_choose":
		return
	if index < 0 or index >= _hand(0).size():
		return
	var removed := _remove_card(0, index)
	_discard_card(removed)
	_log("あなたは 3 の効果で %s を捨てた。" % _card_text(removed))
	_trigger_nine_if_needed(0, removed)
	var remaining := int(pending_attack.get("rank3_remaining", 1)) - 1
	if remaining > 0 and not _hand(0).is_empty():
		pending_attack["rank3_remaining"] = remaining
		prompt = "続けて捨てるカードを選んでください。残り %d 枚。" % remaining
		_refresh()
	else:
		_after_single_attack()


func _resolve_next_group_target() -> void:
	if pending_target_index >= pending_targets.size():
		_end_turn()
		return
	var actor: int = int(pending_attack["actor"])
	var target: int = int(pending_targets[pending_target_index])
	pending_attack["source"] = actor
	pending_attack["target"] = target
	_log("%s の 3 が %s に向かう。" % [_player_name(actor), _player_name(target)])
	_offer_defense(actor, target)


func _after_single_attack() -> void:
	if int(pending_attack.get("rank", 0)) == 3:
		pending_target_index += 1
		_resolve_next_group_target()
	else:
		_end_turn()


func _start_four(actor: int) -> void:
	if actor == 0:
		phase = "choose_color"
		prompt = "4 の効果。赤か黒を宣言してください。"
		_refresh()
	else:
		selected_rank4_color = "red" if rng.randf() < 0.5 else "black"
		_resolve_four(actor, selected_rank4_color)


func _human_choose_color(color_name: String) -> void:
	if phase == "choose_color":
		_resolve_four(0, color_name)


func _resolve_four(actor: int, color_name: String) -> void:
	var label := "赤" if color_name == "red" else "黒"
	_log("%s は 4 で %s を宣言。" % [_player_name(actor), label])
	while not deck.is_empty():
		var card := deck.pop_back() as Dictionary
		if str(card.get("color", "")) == color_name:
			_hand(actor).append(card)
			_log("公開: %s。一致、手札へ加えて継続。" % _card_text(card))
		else:
			_discard_card(card)
			_log("公開: %s。不一致、捨て札へ。" % _card_text(card))
			break
	if deck.is_empty():
		_log("4 の処理中に山札が空になった。")
	_end_turn()


func _start_joker(actor: int) -> void:
	if actor == 0:
		phase = "joker_first"
		pending_attack = {"actor": actor}
		prompt = "Joker: 枚数を調整する最初のプレイヤーを選んでください。"
		_refresh()
	else:
		var alive := _alive_players()
		var first: int = int(alive[rng.randi_range(0, alive.size() - 1)])
		var last: int = int(alive[rng.randi_range(0, alive.size() - 1)])
		_resolve_joker(first, last)


func _human_joker_pick(index: int) -> void:
	if phase == "joker_first":
		pending_attack["joker_first"] = index
		phase = "joker_last"
		prompt = "Joker: 比較先の最後のプレイヤーを選んでください。"
		_refresh()
	elif phase == "joker_last":
		_resolve_joker(int(pending_attack["joker_first"]), index)


func _resolve_joker(first: int, last: int) -> void:
	_log("Joker: %s の手札を %s の枚数に合わせる。" % [_player_name(first), _player_name(last)])
	var diff := _hand(first).size() - _hand(last).size()
	if diff > 0:
		for _i in range(diff):
			if _hand(first).is_empty():
				break
			var idx := 0
			if first != 0:
				idx = _choose_ai_discard(first)
			var card := _remove_card(first, idx)
			_discard_card(card)
			_log("%s が Joker で %s を捨てた。" % [_player_name(first), _card_text(card)])
	elif diff < 0:
		for _i in range(-diff):
			if not _draw_to(first):
				break
		_log("%s が Joker で %d 枚引いた。" % [_player_name(first), -diff])
	else:
		_log("枚数が同じなので Joker は何もしない。")
	_end_turn()


func _end_turn() -> void:
	if done:
		return
	phase = "turn_end"
	eliminated_this_turn.clear()
	for i in range(players.size()):
		if _is_alive(i) and _hand(i).is_empty():
			_player(i)["alive"] = false
			eliminated_this_turn.append(i)
	if not eliminated_this_turn.is_empty():
		for i in eliminated_this_turn:
			_log("%s は手札0枚で脱落。" % _player_name(i))
	if deck.is_empty():
		_finish_by_deck_empty(current_player)
		return
	if _alive_players().size() <= 1:
		var alive := _alive_players()
		if not alive.is_empty():
			_finish_game(int(alive[0]), "最後まで生き残った。")
		return
	current_player = _next_alive_from((current_player + 1) % players.size())
	turn_number += 1
	if _player(current_player)["ai"]:
		phase = "ai_thinking"
		prompt = "%s のターン。" % _player_name(current_player)
		_refresh()
	else:
		_begin_turn()


func _finish_by_deck_empty(last_player: int) -> void:
	var alive := _alive_players()
	if alive.is_empty():
		_finish_game(last_player, "山札が空になった。")
		return
	var best_size := 999
	for i in alive:
		best_size = mini(best_size, _hand(i).size())
	var chosen := int(alive[0])
	for step in range(players.size()):
		var idx := (last_player + step) % players.size()
		if alive.has(idx) and _hand(idx).size() == best_size:
			chosen = idx
			break
	_finish_game(chosen, "山札が空。手札最少 %d 枚。" % best_size)


func _finish_game(winner_index: int, reason: String) -> void:
	winner = winner_index
	done = true
	phase = "game_over"
	prompt = "勝者: %s。%s" % [_player_name(winner_index), reason]
	_log(prompt)
	_refresh()


func _trigger_nine_if_needed(player_index: int, card: Dictionary) -> void:
	if int(card.get("rank", 0)) == 9 and _hand(player_index).is_empty():
		if _draw_to(player_index):
			_log("%s の 9 が受動発動。手札0枚から1枚ドロー。" % _player_name(player_index))


func _build_deck() -> Array:
	var out: Array = []
	var suits := [
		{"suit": "♥", "color": "red"},
		{"suit": "♦", "color": "red"},
		{"suit": "♠", "color": "black"},
		{"suit": "♣", "color": "black"},
	]
	for suit in suits:
		for rank in range(1, 14):
			out.append({
				"rank": rank,
				"suit": suit["suit"],
				"color": suit["color"],
			})
	out.append({"rank": 53, "suit": "Joker", "color": "none"})
	return out


func _shuffle(cards: Array) -> void:
	for i in range(cards.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: Variant = cards[i]
		cards[i] = cards[j]
		cards[j] = tmp


func _draw_to(player_index: int) -> bool:
	if deck.is_empty() or not _is_alive(player_index):
		return false
	_hand(player_index).append(deck.pop_back())
	return true


func _remove_card(player_index: int, hand_index: int) -> Dictionary:
	return (_hand(player_index).pop_at(hand_index) as Dictionary)


func _discard_card(card: Dictionary) -> void:
	discard.append(card)


func _pick_positions(size: int, count: int) -> Array:
	var positions: Array = []
	var pool: Array = []
	for i in range(size):
		pool.append(i)
	for _i in range(mini(count, size)):
		var pool_index := rng.randi_range(0, pool.size() - 1)
		positions.append(int(pool[pool_index]))
		pool.remove_at(pool_index)
	positions.sort()
	positions.reverse()
	return positions


func _choose_ai_discard(player_index: int) -> int:
	var hand := _hand(player_index)
	if hand.is_empty():
		return 0
	var best_idx := 0
	var best_score := 999
	for i in range(hand.size()):
		var rank := int((hand[i] as Dictionary)["rank"])
		var score := rank
		if rank in [5, 6, 11]:
			score += 20
		elif rank in [12, 13]:
			score -= 8
		elif rank == 53:
			score += 8
		if score < best_score:
			best_score = score
			best_idx = i
	return best_idx


func _base_attack_amount(rank: int) -> int:
	if rank == 2:
		return 2
	return 1


func _has_rank(player_index: int, rank: int) -> bool:
	return _find_rank(player_index, rank) >= 0


func _find_rank(player_index: int, rank: int) -> int:
	var hand := _hand(player_index)
	for i in range(hand.size()):
		if int((hand[i] as Dictionary).get("rank", 0)) == rank:
			return i
	return -1


func _alive_opponents(actor: int) -> Array:
	var out: Array = []
	for i in range(players.size()):
		if i != actor and _is_alive(i):
			out.append(i)
	return out


func _alive_players() -> Array:
	var out: Array = []
	for i in range(players.size()):
		if _is_alive(i):
			out.append(i)
	return out


func _next_alive_from(start_index: int) -> int:
	if players.is_empty():
		return 0
	for step in range(players.size()):
		var idx := (start_index + step) % players.size()
		if _is_alive(idx):
			return idx
	return start_index


func _is_alive(index: int) -> bool:
	return index >= 0 and index < players.size() and bool(_player(index).get("alive", false))


func _player(index: int) -> Dictionary:
	if index < 0 or index >= players.size():
		return {}
	return players[index] as Dictionary


func _hand(index: int) -> Array:
	return (_player(index).get("hand", []) as Array)


func _player_name(index: int) -> String:
	return str(_player(index).get("name", "P%d" % index))


func _card_text(card: Dictionary) -> String:
	var rank := int(card.get("rank", 0))
	if rank == 53:
		return "Joker"
	var label := str(rank)
	if rank == 1:
		label = "A"
	elif rank == 11:
		label = "J"
	elif rank == 12:
		label = "Q"
	elif rank == 13:
		label = "K"
	return "%s%s" % [str(card.get("suit", "")), label]


func _rank_effect_text(rank: int) -> String:
	match rank:
		1:
			return "伏せ札1枚を捨てさせる"
		2:
			return "伏せ札2枚を捨てさせる"
		3:
			return "全員が自分で1枚捨てる"
		4:
			return "色宣言。山札公開を連続処理"
		5:
			return "防御: 攻撃反転"
		6:
			return "防御: 攻撃無効"
		7:
			return "伏せ札1枚を奪う"
		8:
			return "山札から1枚引く"
		9:
			return "攻撃で捨てられ手札0なら1枚引く"
		10:
			return "A と同じ攻撃"
		11:
			return "攻撃前に重ねて +1"
		12, 13:
			return "効果なし"
		53:
			return "2人を選び手札枚数を合わせる"
	return ""


func _build_ui() -> void:
	root_ui = Control.new()
	root_ui.position = Vector2.ZERO
	add_child(root_ui)

	if table_texture != null:
		var bg := TextureRect.new()
		bg.texture = table_texture
		bg.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		bg.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		bg.set_anchors_preset(Control.PRESET_FULL_RECT)
		root_ui.add_child(bg)
	else:
		var bg_fallback := ColorRect.new()
		bg_fallback.color = Color(0.235, 0.235, 0.225)
		bg_fallback.set_anchors_preset(Control.PRESET_FULL_RECT)
		root_ui.add_child(bg_fallback)

	var shade := ColorRect.new()
	shade.color = Color(1.0, 1.0, 1.0, 0.04)
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_ui.add_child(shade)

	setup_panel = VBoxContainer.new()
	setup_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 40)
	setup_panel.add_theme_constant_override("separation", 18)
	root_ui.add_child(setup_panel)

	var title := Label.new()
	title.text = "エンブレム 53"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(0.06, 0.055, 0.05))
	title.add_theme_color_override("font_shadow_color", Color(1.0, 1.0, 1.0, 0.75))
	title.add_theme_constant_override("shadow_offset_x", 2)
	title.add_theme_constant_override("shadow_offset_y", 2)
	setup_panel.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "トランプ52枚 + Joker 1枚の捨札サバイバル"
	subtitle.add_theme_font_size_override("font_size", 20)
	subtitle.add_theme_color_override("font_color", Color(0.12, 0.12, 0.115))
	setup_panel.add_child(subtitle)

	var count_row := HBoxContainer.new()
	count_row.add_theme_constant_override("separation", 10)
	setup_panel.add_child(count_row)
	for count in range(MIN_PLAYERS, MAX_PLAYERS + 1):
		var btn := _make_button("%d人で開始" % count)
		btn.custom_minimum_size = Vector2(150, 48)
		btn.pressed.connect(func(c := count): _start_match(c))
		count_row.add_child(btn)

	var rule := RichTextLabel.new()
	rule.bbcode_enabled = true
	rule.fit_content = true
	rule.text = "[color=#111111]目的:[/color] 山札が尽きた時点で手札が最少なら勝利。手札0枚でターン終了を迎えると脱落。\n[color=#111111]操作:[/color] 自分のターンは手札をクリックして捨てます。攻撃・ジョーカー・防御は画面下のボタンで選択します。"
	rule.add_theme_font_size_override("normal_font_size", 18)
	rule.add_theme_color_override("default_color", Color(0.10, 0.095, 0.085))
	setup_panel.add_child(rule)

	game_panel = VBoxContainer.new()
	game_panel.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT, Control.PRESET_MODE_MINSIZE, 14)
	game_panel.add_theme_constant_override("separation", 5)
	root_ui.add_child(game_panel)

	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	game_panel.add_child(top)
	phase_label = _make_label("", 19, Color(0.08, 0.08, 0.075))
	top.add_child(phase_label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(spacer)
	var new_btn := _make_button("新規ゲーム")
	new_btn.pressed.connect(func(): _reset_game(false))
	top.add_child(new_btn)

	var table_body := HBoxContainer.new()
	table_body.add_theme_constant_override("separation", 16)
	table_body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	game_panel.add_child(table_body)

	var play_area := VBoxContainer.new()
	play_area.add_theme_constant_override("separation", 5)
	play_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_body.add_child(play_area)

	player_row = HBoxContainer.new()
	player_row.add_theme_constant_override("separation", 10)
	play_area.add_child(player_row)

	var pile_center := CenterContainer.new()
	pile_center.custom_minimum_size = Vector2(0, 88)
	play_area.add_child(pile_center)

	var pile_row := HBoxContainer.new()
	pile_row.add_theme_constant_override("separation", 30)
	pile_center.add_child(pile_row)

	var deck_pile := _make_pile_card(true)
	deck_pile_label = deck_pile.find_child("Value", true, false) as Label
	pile_row.add_child(deck_pile)

	var discard_pile := _make_pile_card(false)
	discard_pile_label = discard_pile.find_child("Value", true, false) as Label
	pile_row.add_child(discard_pile)

	prompt_label = _make_label("", 17, Color(0.08, 0.08, 0.075))
	prompt_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	prompt_label.custom_minimum_size = Vector2(0, 28)
	play_area.add_child(prompt_label)

	action_row = HBoxContainer.new()
	action_row.add_theme_constant_override("separation", 8)
	play_area.add_child(action_row)

	hand_area = Control.new()
	hand_area.custom_minimum_size = Vector2(0, CARD_H + 18)
	hand_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hand_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	play_area.add_child(hand_area)

	var log_panel := VBoxContainer.new()
	log_panel.custom_minimum_size = Vector2(270, 0)
	log_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	table_body.add_child(log_panel)

	var log_title := _make_label("ログ", 16, Color(0.08, 0.08, 0.075))
	log_panel.add_child(log_title)

	log_box = RichTextLabel.new()
	log_box.bbcode_enabled = true
	log_box.scroll_following = true
	log_box.size_flags_vertical = Control.SIZE_EXPAND_FILL
	log_box.custom_minimum_size = Vector2(270, 0)
	log_box.add_theme_font_size_override("normal_font_size", 15)
	log_box.add_theme_color_override("default_color", Color(0.14, 0.13, 0.12))
	log_box.add_theme_stylebox_override("normal", _log_style())
	log_panel.add_child(log_box)


func _sync_ui_to_viewport() -> void:
	if root_ui == null:
		return
	root_ui.size = get_viewport_rect().size


func _show_setup() -> void:
	if setup_panel:
		setup_panel.visible = true
	if game_panel:
		game_panel.visible = false


func _show_game() -> void:
	setup_panel.visible = false
	game_panel.visible = true


func _refresh() -> void:
	if root_ui == null:
		return
	setup_panel.visible = phase == "setup"
	game_panel.visible = phase != "setup"
	if phase == "setup":
		return
	phase_label.text = "Turn %d / %s" % [turn_number, _player_name(current_player) if not players.is_empty() else "-"]
	deck_pile_label.text = "山札\n%d" % deck.size()
	discard_pile_label.text = "捨て札\n%s" % (_card_text(discard[-1]) if not discard.is_empty() else "なし")
	prompt_label.text = prompt
	_rebuild_players()
	_rebuild_actions()
	_rebuild_hand()


func _rebuild_players() -> void:
	_clear_children(player_row)
	for i in range(players.size()):
		var p := _player(i)
		var box := VBoxContainer.new()
		box.custom_minimum_size = Vector2(130, 70)
		var panel := PanelContainer.new()
		panel.add_theme_stylebox_override("panel", _panel_style(Color(0.945, 0.93, 0.87, 0.96) if i != current_player else Color(0.72, 0.58, 0.27, 0.98)))
		box.add_child(panel)
		var inner := VBoxContainer.new()
		inner.add_theme_constant_override("separation", 4)
		panel.add_child(inner)
		var name := _make_label(str(p["name"]), 15, Color(0.08, 0.08, 0.075))
		inner.add_child(name)
		var state := "脱落" if not bool(p["alive"]) else "手札 %d" % _hand(i).size()
		var info := _make_label(state, 13, Color(0.22, 0.20, 0.17))
		inner.add_child(info)
		if bool(p["alive"]):
			inner.add_child(_make_card_back_strip(_hand(i).size()))
		if i == winner:
			inner.add_child(_make_label("WINNER", 14, Color(0.83, 0.12, 0.10)))
		player_row.add_child(box)


func _rebuild_actions() -> void:
	_clear_children(action_row)
	if phase == "jack_boost":
		var use := _make_button("11を重ねる")
		use.disabled = not _has_rank(0, 11)
		use.pressed.connect(_human_use_jack)
		action_row.add_child(use)
		var skip := _make_button("対象選択へ")
		skip.pressed.connect(_human_finish_jacks)
		action_row.add_child(skip)
	elif phase == "choose_target":
		for i in _alive_opponents(0):
			var b := _make_button("%s (%d枚)" % [_player_name(i), _hand(i).size()])
			b.pressed.connect(func(target: int = int(i)): _human_choose_target(target))
			action_row.add_child(b)
	elif phase == "defense":
		if _has_rank(0, 5):
			var r := _make_button("5 反転")
			r.pressed.connect(func(): _human_defense(5))
			action_row.add_child(r)
		if _has_rank(0, 6):
			var c := _make_button("6 無効")
			c.pressed.connect(func(): _human_defense(6))
			action_row.add_child(c)
		var n := _make_button("防御しない")
		n.pressed.connect(func(): _human_defense(0))
		action_row.add_child(n)
	elif phase == "choose_color":
		var red := _make_button("赤")
		red.pressed.connect(func(): _human_choose_color("red"))
		action_row.add_child(red)
		var black := _make_button("黒")
		black.pressed.connect(func(): _human_choose_color("black"))
		action_row.add_child(black)
	elif phase in ["joker_first", "joker_last"]:
		for i in _alive_players():
			var jb := _make_button("%s (%d枚)" % [_player_name(i), _hand(i).size()])
			jb.pressed.connect(func(target: int = int(i)): _human_joker_pick(target))
			action_row.add_child(jb)
	elif phase == "game_over":
		var again := _make_button("もう一度")
		again.pressed.connect(func(): _start_match(player_count))
		action_row.add_child(again)


func _rebuild_hand() -> void:
	_clear_children(hand_area)
	if players.is_empty():
		return
	var hand := _hand(0)
	var count := hand.size()
	var area_width := hand_area.size.x
	if area_width < 20.0:
		area_width = maxf(420.0, root_ui.size.x - 380.0)
	var center_x := area_width * 0.5
	var spacing := 74.0
	if count > 1:
		spacing = minf(74.0, (area_width - CARD_W) / float(count - 1))
		spacing = maxf(spacing, 48.0)
	var total_width := spacing * float(maxi(count - 1, 0))
	var start_x := center_x - (total_width * 0.5) - (CARD_W * 0.5)
	for i in range(count):
		var card := _hand(0)[i] as Dictionary
		var btn := Button.new()
		btn.custom_minimum_size = Vector2(CARD_W, CARD_H)
		btn.size = Vector2(CARD_W, CARD_H)
		btn.pivot_offset = Vector2(CARD_W * 0.5, CARD_H)
		btn.text = "%s\n\n%s" % [_card_text(card), _rank_effect_text(int(card["rank"]))]
		btn.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		btn.add_theme_font_size_override("font_size", 13)
		btn.add_theme_color_override("font_color", Color(0.12, 0.13, 0.12))
		btn.add_theme_color_override("font_hover_color", Color(0.10, 0.11, 0.10))
		btn.add_theme_color_override("font_pressed_color", Color(0.10, 0.11, 0.10))
		btn.add_theme_color_override("font_focus_color", Color(0.10, 0.11, 0.10))
		btn.add_theme_stylebox_override("normal", _card_style(card))
		btn.add_theme_stylebox_override("hover", _card_style(card, true))
		btn.add_theme_stylebox_override("pressed", _card_style(card, true))
		btn.disabled = not (phase == "discard" or phase == "rank3_choose")
		if phase == "discard":
			btn.pressed.connect(func(index := i): _human_discard(index))
		elif phase == "rank3_choose":
			btn.pressed.connect(func(index := i): _human_rank3_discard(index))
		var fan_offset := float(i) - (float(count - 1) * 0.5)
		var base_position := Vector2(start_x + spacing * float(i), 8.0 + absf(fan_offset) * 5.0)
		btn.position = base_position
		btn.rotation_degrees = fan_offset * 7.0
		btn.set_meta("base_position", base_position)
		btn.set_meta("base_rotation", btn.rotation_degrees)
		btn.mouse_entered.connect(func(card_btn := btn): _focus_hand_card(card_btn, true))
		btn.mouse_exited.connect(func(card_btn := btn): _focus_hand_card(card_btn, false))
		btn.focus_entered.connect(func(card_btn := btn): _focus_hand_card(card_btn, true))
		btn.focus_exited.connect(func(card_btn := btn): _focus_hand_card(card_btn, false))
		hand_area.add_child(btn)


func _focus_hand_card(card_btn: Button, focused: bool) -> void:
	if not is_instance_valid(card_btn):
		return
	var base_position := card_btn.get_meta("base_position") as Vector2
	var base_rotation := float(card_btn.get_meta("base_rotation"))
	if focused and not card_btn.disabled:
		card_btn.position = base_position + Vector2(0.0, -24.0)
		card_btn.rotation_degrees = base_rotation * 0.45
		card_btn.scale = Vector2(1.08, 1.08)
		card_btn.z_index = 20
	else:
		card_btn.position = base_position
		card_btn.rotation_degrees = base_rotation
		card_btn.scale = Vector2.ONE
		card_btn.z_index = 0


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(116, 42)
	b.add_theme_font_size_override("font_size", 16)
	b.add_theme_stylebox_override("normal", _button_style(Color(0.72, 0.58, 0.27)))
	b.add_theme_stylebox_override("hover", _button_style(Color(0.82, 0.16, 0.13)))
	b.add_theme_stylebox_override("pressed", _button_style(Color(0.50, 0.42, 0.22)))
	b.add_theme_color_override("font_color", Color(1.0, 0.98, 0.92))
	return b


func _make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	return l


func _make_pile_card(is_deck: bool) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(92, 98)
	panel.add_theme_stylebox_override("panel", _pile_style(is_deck))

	var stack := VBoxContainer.new()
	stack.name = "Stack"
	stack.alignment = BoxContainer.ALIGNMENT_CENTER
	stack.add_theme_constant_override("separation", 6)
	panel.add_child(stack)

	if is_deck and card_back_texture != null:
		var back := TextureRect.new()
		back.custom_minimum_size = Vector2(34, 46)
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		back.texture = card_back_texture
		stack.add_child(back)
	else:
		var suit := _make_label("♠", 18, Color(0.08, 0.08, 0.075))
		suit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		stack.add_child(suit)

	var value := _make_label("", 13, Color(0.08, 0.08, 0.075))
	value.name = "Value"
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(value)
	return panel


func _button_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = Color(0.07, 0.065, 0.06, 0.58)
	s.border_width_left = 1
	s.border_width_top = 1
	s.border_width_right = 1
	s.border_width_bottom = 1
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _pile_style(is_deck: bool) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.945, 0.93, 0.87, 0.98)
	s.border_color = Color(0.08, 0.08, 0.075, 0.92) if is_deck else Color(0.82, 0.16, 0.13, 0.92)
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.shadow_color = Color(0.0, 0.0, 0.0, 0.34)
	s.shadow_size = 8
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	return s


func _panel_style(color: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.border_color = Color(0.08, 0.08, 0.075, 0.72)
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _card_style(card: Dictionary, hover := false) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	var is_red := str(card.get("color", "")) == "red"
	s.bg_color = Color(0.965, 0.955, 0.925) if not hover else Color(1.0, 0.985, 0.93)
	s.border_color = Color(0.86, 0.17, 0.13) if is_red else Color(0.08, 0.08, 0.075)
	if int(card.get("rank", 0)) == 53:
		s.border_color = Color(0.72, 0.58, 0.27)
	s.border_width_left = 3
	s.border_width_top = 3
	s.border_width_right = 3
	s.border_width_bottom = 3
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 8
	s.content_margin_right = 8
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _log_style() -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.955, 0.945, 0.91, 0.94)
	s.border_color = Color(0.08, 0.08, 0.075, 0.62)
	s.border_width_left = 2
	s.border_width_top = 2
	s.border_width_right = 2
	s.border_width_bottom = 2
	s.corner_radius_top_left = 8
	s.corner_radius_top_right = 8
	s.corner_radius_bottom_left = 8
	s.corner_radius_bottom_right = 8
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	return s


func _make_card_back_strip(count: int) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", -10)
	row.custom_minimum_size = Vector2(0, 30)
	var shown := mini(count, 5)
	for i in range(shown):
		var back := TextureRect.new()
		back.custom_minimum_size = Vector2(22, 30)
		back.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		back.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
		back.texture = card_back_texture
		row.add_child(back)
	if count > shown:
		var more := _make_label("+%d" % (count - shown), 12, Color(0.92, 0.78, 0.42))
		row.add_child(more)
	return row


func _clear_children(node: Node) -> void:
	for child in node.get_children():
		node.remove_child(child)
		child.queue_free()


func _log(message: String) -> void:
	if log_box != null:
		log_box.append_text("[color=#24211d]%s[/color]\n" % message)


# --- test hooks ---
func enable_test_mode(enabled: bool) -> void:
	test_mode = enabled


func force_reset_for_test(test_seed: int) -> void:
	rng.seed = test_seed
	_start_match(4)


func step_for_test(delta: float, inputs: Dictionary) -> void:
	last_test_inputs = inputs.duplicate(true)
	elapsed += delta
	custom_metrics = {
		"phase": phase,
		"deck": deck.size(),
		"discard": discard.size(),
		"players": players.size(),
		"turn": turn_number,
	}


func get_metrics() -> Dictionary:
	return {
		"elapsed": elapsed,
		"done": done,
		"last_test_inputs": last_test_inputs.duplicate(true),
		"custom_metrics": custom_metrics.duplicate(true),
	}


func step_for_test_dict(delta: float, inputs: Dictionary) -> void:
	step_for_test(delta, inputs)


func get_test_input_channels() -> Array:
	return []
