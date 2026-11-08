extends RefCounted
class_name BattleRuntimeConfig
## 竖屏战斗演示布局常量（大道仙途式左右对站，非旧 battle_page 左下角站位）。

const CANVAS_W := 1080
const CANVAS_H := 2340

## 角色显示高度：约战场可见高度的五分之一（260–300）。
const HERO_DISPLAY_H := 280.0
const BOSS_DISPLAY_H := 300.0

## 脚底同一水平线（画面中段偏下，下方约 1/3 留给血条/战报）。
const FEET_Y := 1280.0

## 左右中心 X：中间留出技能空档。
const HERO_CENTER_X := 260.0
const BOSS_CENTER_X := 820.0

## 背景区域（黑风岭战斗背景 1080×1640，贴在战场上半）。
const BG_TOP := 0.0
const BG_H := 1640.0

## 首领 HUD（名 + 血条）
const BOSS_HUD_TOP := 72.0
const BOSS_HUD_H := 96.0

## 主角 HUD（角色脚底下方）
const HERO_HUD_TOP := 1320.0
const HERO_HUD_H := 88.0

## 下方战报区（约屏高 1/3）
const LOG_TOP := 1560.0
const LOG_BOTTOM_PAD := 48.0

const TEX_HERO := "res://assets/art/q/sprites/player_fight.png"
const TEX_BOSS := "res://assets/art/q/sprites/boss_bear.png"
const TEX_BG := "res://assets/art/q/bg/bg_battle_heifeng_1080x1640.webp"

const HERO_NAME := "少年剑修"
const BOSS_NAME := "黑风熊王"
const HERO_HP := 12800
const HERO_HP_MAX := 12800
const BOSS_HP := 86000
const BOSS_HP_MAX := 100000
