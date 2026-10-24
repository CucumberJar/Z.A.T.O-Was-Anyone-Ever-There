extends CanvasLayer
## Interactive calibration of the KOD research supercomputer.
## Opens over the current world; completion hands control back to main_indoor.gd.

signal experiment_failed(feedback_enabled: bool)
signal cancelled

const TARGETS = [4, 7, 2]
const COLOR_DARK := Color("091b18")
const COLOR_GREEN := Color("97e2bd")
const COLOR_AMBER := Color("e8ba6a")
const COLOR_RED := Color("ec847b")
const COLOR_TEXT := Color("dcece2")

@onready var root: Control = $Root
@onready var frame: Panel = $Root/Frame
@onready var monitor: Panel = $Root/Frame/Monitor
@onready var heading: Label = $Root/Frame/Heading
@onready var subheading: Label = $Root/Frame/Subheading
@onready var instructions: Label = $Root/Frame/Instructions
@onready var report: Label = $Root/Frame/Monitor/Report
@onready var percentage: Label = $Root/Frame/Monitor/Percentage
@onready var progress_bar: ProgressBar = $Root/Frame/Monitor/Progress
@onready var feedback: CheckButton = $Root/Frame/Feedback
@onready var launch: Button = $Root/Frame/Launch
@onready var cancel_button: Button = $Root/Frame/Cancel
@onready var acknowledge: Button = $Root/Frame/Acknowledge

@onready var readouts: Array[Label] = [
    $Root/Frame/Channel0/Value,
    $Root/Frame/Channel1/Value,
    $Root/Frame/Channel2/Value,
]
@onready var descriptions: Array[Label] = [
    $Root/Frame/Channel0/Diagnostic,
    $Root/Frame/Channel1/Diagnostic,
    $Root/Frame/Channel2/Diagnostic,
]
@onready var channel_frames: Array[Panel] = [
    $Root/Frame/Channel0,
    $Root/Frame/Channel1,
    $Root/Frame/Channel2,
]

var values: Array[int] = [1, 5, 7]
var has_manual := false
var state := "SETUP"  # SETUP / RUNNING / BSOD
var progress := 0.0
var feedback_on_at_launch := true

func _ready() -> void:
    process_mode = Node.PROCESS_MODE_ALWAYS
    root.mouse_filter = Control.MOUSE_FILTER_STOP
    _style()
    for i in range(3):
        var left: Button = channel_frames[i].get_node("Minus") as Button
        var right: Button = channel_frames[i].get_node("Plus") as Button
        left.pressed.connect(_change_channel.bind(i, -1))
        right.pressed.connect(_change_channel.bind(i, 1))
    launch.pressed.connect(_launch)
    cancel_button.pressed.connect(_cancel)
    acknowledge.pressed.connect(_acknowledge)
    feedback.toggled.connect(_on_feedback_changed)
    acknowledge.hide()
    _refresh_setup()

func open(manual_read: bool) -> void:
    has_manual = manual_read
    feedback.button_pressed = true
    state = "SETUP"
    progress = 0.0
    _refresh_setup()
    cancel_button.grab_focus()

func _process(delta: float) -> void:
    if state != "RUNNING":
        return
    # A visible transfer, then an intentional crash at exactly 99.99%.
    progress = minf(99.99, progress + 23.0 * delta)
    progress_bar.value = progress
    percentage.text = "%05.2f%%" % progress
    if progress >= 99.99:
        _show_bsod()

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey:
        var key: InputEventKey = event as InputEventKey
        if not key.pressed or key.echo:
            return
        if key.keycode == KEY_ESCAPE and state == "SETUP":
            _cancel()
            get_viewport().set_input_as_handled()
        elif (key.keycode == KEY_ENTER or key.keycode == KEY_KP_ENTER) and state == "BSOD":
            _acknowledge()
            get_viewport().set_input_as_handled()

func _style_box(bg: Color, outline: Color, border: int = 1) -> StyleBoxFlat:
    var box := StyleBoxFlat.new()
    box.bg_color = bg
    box.border_color = outline
    box.set_border_width_all(border)
    box.set_corner_radius_all(0)
    box.set_content_margin_all(5.0)
    return box

func _style_button(button: Button, primary: bool = false) -> void:
    button.add_theme_stylebox_override("normal", _style_box(Color("214239") if primary else Color("182d2a"), COLOR_GREEN if primary else Color("507065")))
    button.add_theme_stylebox_override("hover", _style_box(Color("34594b"), COLOR_AMBER, 2))
    button.add_theme_stylebox_override("pressed", _style_box(Color("4b634b"), COLOR_AMBER))
    button.add_theme_stylebox_override("disabled", _style_box(Color("17211e"), Color("33443e")))
    button.add_theme_stylebox_override("focus", _style_box(Color.TRANSPARENT, COLOR_AMBER))
    button.add_theme_color_override("font_color", COLOR_TEXT)
    button.add_theme_color_override("font_hover_color", COLOR_TEXT)
    button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
    button.add_theme_color_override("font_disabled_color", Color("566f63"))
    button.add_theme_font_size_override("font_size", 11)

func _style() -> void:
    frame.add_theme_stylebox_override("panel", _style_box(Color("101f1d"), Color("8eafa2"), 2))
    monitor.add_theme_stylebox_override("panel", _style_box(Color("06170f"), Color("426f57"), 2))
    for panel in channel_frames:
        panel.add_theme_stylebox_override("panel", _style_box(Color("172b26"), Color("3b594e")))
        _style_button(panel.get_node("Minus") as Button)
        _style_button(panel.get_node("Plus") as Button)
    for button in [launch, cancel_button, acknowledge]:
        _style_button(button, button == launch or button == acknowledge)
    for label in [heading, subheading, instructions, report, percentage]:
        label.add_theme_color_override("font_color", COLOR_GREEN)
    percentage.add_theme_color_override("font_color", COLOR_AMBER)
    for label in readouts:
        label.add_theme_color_override("font_color", COLOR_AMBER)
    for label in descriptions:
        label.add_theme_color_override("font_color", COLOR_TEXT)
    feedback.add_theme_color_override("font_color", COLOR_TEXT)
    progress_bar.add_theme_stylebox_override("background", _style_box(Color("152b20"), Color("304838")))
    progress_bar.add_theme_stylebox_override("fill", _style_box(COLOR_GREEN, COLOR_GREEN, 0))
    progress_bar.show_percentage = false

func _change_channel(index: int, delta: int) -> void:
    if state != "SETUP":
        return
    values[index] = clampi(values[index] + delta, 0, 9)
    _refresh_setup()

func _refresh_setup() -> void:
    if not is_node_ready():
        return
    var correct := true
    for i in range(3):
        readouts[i].text = "%02d" % values[i]
        if values[i] < TARGETS[i]:
            descriptions[i].text = "НИЖЕ НОРМЫ  ↑"
            descriptions[i].add_theme_color_override("font_color", COLOR_AMBER)
            correct = false
        elif values[i] > TARGETS[i]:
            descriptions[i].text = "ВЫШЕ НОРМЫ  ↓"
            descriptions[i].add_theme_color_override("font_color", COLOR_AMBER)
            correct = false
        else:
            descriptions[i].text = "СОВПАДЕНИЕ  ✓"
            descriptions[i].add_theme_color_override("font_color", COLOR_GREEN)
    launch.disabled = not correct
    if has_manual:
        instructions.text = "РЕГЛАМЕНТ 12-Б: А=04, Б=07, В=02. Перед пуском отключить обратную связь."
    else:
        instructions.text = "ИНСТРУКЦИЯ НЕ ПРЕДЪЯВЛЕНА. Подберите параметры по диагностике."
    if correct:
        report.text = "КАНАЛЫ СОГЛАСОВАНЫ. УСТАНОВКА ОЖИДАЕТ ПУСКА."
    else:
        report.text = "АСУ «КОД»: ОШИБКА КАЛИБРОВКИ. СВЕРЬТЕ ТРИ КАНАЛА."
    percentage.text = "00.00%"
    progress_bar.value = 0.0

func _on_feedback_changed(_pressed: bool) -> void:
    if state == "SETUP":
        _refresh_setup()

func _launch() -> void:
    if state != "SETUP" or launch.disabled:
        return
    state = "RUNNING"
    feedback_on_at_launch = feedback.button_pressed
    feedback.disabled = true
    cancel_button.disabled = true
    launch.disabled = true
    for panel in channel_frames:
        var minus_button: Button = panel.get_node("Minus") as Button
        var plus_button: Button = panel.get_node("Plus") as Button
        minus_button.disabled = true
        plus_button.disabled = true
    instructions.text = "ИНИЦИАЛИЗАЦИЯ ИСТОЧНИКА... ОЖИДАЙТЕ ПОДТВЕРЖДЕНИЯ."
    report.text = "КОММУТАЦИЯ / СТАРТ / МОДУЛЬ «КОНТУР» / ДОСТУП ОПЕРАТОРА"

func _show_bsod() -> void:
    state = "BSOD"
    $Root/Backdrop.color = Color("08229b")
    for panel in channel_frames:
        panel.hide()
    feedback.hide()
    launch.hide()
    cancel_button.hide()
    monitor.size = Vector2(570, 180)
    report.size = Vector2(540, 111)
    monitor.add_theme_stylebox_override("panel", _style_box(Color("0926a8"), Color("c8defc"), 2))
    frame.add_theme_stylebox_override("panel", _style_box(Color("061783"), Color("94b9fa"), 2))
    for node in [heading, subheading, instructions, report, percentage]:
        node.add_theme_color_override("font_color", Color.WHITE)
    heading.text = "*** STOP: 0x0000C0DE ***"
    subheading.text = "КРИТИЧЕСКИЙ СБОЙ УСТАНОВКИ / 1987"
    percentage.text = "99.99%"
    progress_bar.value = 99.99
    if feedback_on_at_launch:
        report.text = "FATAL_FEEDBACK_LOOP\n\nКАНАЛ ОБРАТНОЙ СВЯЗИ ПЕРЕПОЛНЕН.\nОШИБКА ОПЕРАТОРА.\nВНУТРЕННЯЯ РЕАЛЬНОСТЬ НЕ ОТВЕЧАЕТ."
    else:
        report.text = "EXTERNAL_CODE_OVERRIDE\n\nКОМАНДА БЛОКИРОВКИ ПРИНЯТА.\nКОМАНДА НЕ ВЫПОЛНЕНА.\nИСТОЧНИК ИЗМЕНИЛ РЕГЛАМЕНТ."
    instructions.text = "СИНХРОНИЗАЦИЯ НЕВОЗМОЖНА.\nНЕ ПЕРЕЗАГРУЖАЙТЕ ВСЕЛЕННУЮ БЕЗ СОГЛАСОВАНИЯ."
    acknowledge.show()
    acknowledge.text = "ПОДТВЕРДИТЬ СБОЙ ↵"
    acknowledge.grab_focus()

func _acknowledge() -> void:
    if state != "BSOD":
        return
    experiment_failed.emit(feedback_on_at_launch)
    queue_free()

func _cancel() -> void:
    if state != "SETUP":
        return
    cancelled.emit()
    queue_free()
