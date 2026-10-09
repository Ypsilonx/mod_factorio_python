"""Materiály Pythonatoru s patinou Factoria – jen pro Cycles. Špinavé a opotřebené jsou kovové části
(sokl, skříňka, svorkovnice); displej je čistý a součástky jen lehce zaprášené.
Barvy v lineárním RGB; laditelné hodnoty jsou v této tabulce volání (parametr dust = míra prachu)."""

import pyntr_layout as L
import pyntr_patina as P
import pyntr_pcb


def build_all(work_dir):
    """Všechny materiály modelu (jméno → materiál); textura desky se vygeneruje do work_dir."""
    return {
        # Kov a nátěry
        "plinth": P.weathered_metal("PYNTR_plinth", (0.035, 0.034, 0.033), rust=0.55, wear=0.8, tread_plate=True),
        "housing": P.chipped_paint("PYNTR_housing", (0.07, 0.075, 0.085), chipping=0.6),
        "stripe": P.chipped_paint("PYNTR_stripe", (0.55, 0.38, 0.02), chipping=0.55),   # žluté výstražné pruhy
        "frame": P.weathered_metal("PYNTR_frame", (0.09, 0.09, 0.095), rust=0.45, wear=0.8),
        "screw": P.weathered_metal("PYNTR_screw", (0.4, 0.4, 0.42), rust=0.3, wear=0.2, metallic=0.9, roughness=0.35),
        "standoff": P.weathered_metal("PYNTR_standoff", (0.45, 0.33, 0.13), rust=0.25, wear=0.4, metallic=0.9,
                                      roughness=0.4),
        "heatsink": P.weathered_metal("PYNTR_heatsink", (0.4, 0.42, 0.45), rust=0.1, wear=0.5, metallic=0.9,
                                      roughness=0.4),
        "vent": P.void("PYNTR_vent"),
        # Deska a součástky
        "pcb": P.pcb("PYNTR_pcb", pyntr_pcb.make_image(work_dir), L.PCB_SIZE, dust=0.3),
        "silk": P.grimy("PYNTR_silk", (0.7, 0.7, 0.66), dust=0.5),
        "chip": P.grimy("PYNTR_chip", (0.012, 0.012, 0.014), roughness=0.3, dust=0.12),
        "pin": P.weathered_metal("PYNTR_pin", (0.5, 0.5, 0.52), rust=0.15, wear=0.2, metallic=1.0, roughness=0.3),
        "gold": P.weathered_metal("PYNTR_gold", (0.6, 0.38, 0.08), rust=0.05, wear=0.1, metallic=1.0, roughness=0.3),
        "cap_blue": P.grimy("PYNTR_cap_blue", (0.02, 0.07, 0.3), roughness=0.3, dust=0.12),
        "cap_top": P.weathered_metal("PYNTR_cap_top", (0.5, 0.5, 0.53), rust=0.2, wear=0.2, metallic=1.0,
                                     roughness=0.3),
        "resistor": P.grimy("PYNTR_resistor", (0.4, 0.3, 0.17), dust=0.15),
        "crystal": P.weathered_metal("PYNTR_crystal", (0.55, 0.55, 0.58), rust=0.15, wear=0.3, metallic=1.0,
                                     roughness=0.3),
        "copper_coil": P.weathered_metal("PYNTR_copper_coil", (0.5, 0.2, 0.06), rust=0.3, wear=0.1, metallic=1.0,
                                         roughness=0.35),
        "fuse_glass": P.grimy("PYNTR_fuse_glass", (0.35, 0.36, 0.33), roughness=0.1, dust=0.15),
        "header": P.grimy("PYNTR_header", (0.01, 0.01, 0.01), dust=0.15),
        "terminal_block": P.grimy("PYNTR_terminal_block", (0.02, 0.15, 0.05), dust=0.7),
        "brass": P.weathered_metal("PYNTR_brass", (0.4, 0.28, 0.1), rust=0.35, wear=0.5, metallic=1.0,
                                   roughness=0.4),
        "wire_red": P.grimy("PYNTR_wire_red", (0.5, 0.025, 0.015), roughness=0.45, dust=0.5),
        "wire_green": P.grimy("PYNTR_wire_green", (0.025, 0.33, 0.04), roughness=0.45, dust=0.5),
        "jumper_yellow": P.grimy("PYNTR_jumper_yellow", (0.65, 0.45, 0.02), dust=0.2),
        "jumper_blue": P.grimy("PYNTR_jumper_blue", (0.03, 0.12, 0.6), dust=0.2),
        "jumper_orange": P.grimy("PYNTR_jumper_orange", (0.7, 0.18, 0.02), dust=0.2),
        "jumper_white": P.grimy("PYNTR_jumper_white", (0.6, 0.6, 0.58), dust=0.25),
        # Displej a LED
        "lcd_bezel": P.grimy("PYNTR_lcd_bezel", (0.02, 0.02, 0.022), roughness=0.35, dust=0.1),
        "lcd_screen": P.grimy("PYNTR_lcd_screen", (0.005, 0.03, 0.012), roughness=0.08, dust=0.0),
        "lcd_text": P.grimy("PYNTR_lcd_text", (0.02, 0.2, 0.05), roughness=0.3, dust=0.0,
                            emission=((0.15, 1.0, 0.3), 3.0)),
        "dupont": P.grimy("PYNTR_dupont", (0.008, 0.008, 0.009), roughness=0.4, dust=0.15),   # konektory drátků
        "ferrule": P.weathered_metal("PYNTR_ferrule", (0.55, 0.55, 0.57), rust=0.05, wear=0.1, metallic=1.0,
                                     roughness=0.3),                                   # dutinky drátů
        "led_off": P.grimy("PYNTR_led_off", (0.05, 0.05, 0.04), roughness=0.1, dust=0.0),
    }
