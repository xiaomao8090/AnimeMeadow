<div align="center">

<img src="art/branding/animemeadow-logo-v1.png" alt="AnimeMeadow" width="520">

### 一片走不到尽头的草原。

*An endless, hand-crafted-feeling meadow to wander, breathe, and make friends in.*

![Engine](https://img.shields.io/badge/Godot-4.7-478CBF?logo=godotengine&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6)
![Status](https://img.shields.io/badge/status-in%20development-E8A33D)
![Renderer](https://img.shields.io/badge/renderer-Forward%2B-6BA368)

</div>

---

## 关于游戏

**AnimeMeadow** 是一款卡通渲染风格的治愈系漫游游戏。

没有任务，没有倒计时，也没有敌人。你只是一个圆滚滚的小旅人，背着背包，走进一片随风起伏、永远生成不完的草原。
清晨听鸟叫，黄昏追蝴蝶，夜里看萤火虫；摸摸路边的兔子，喂小鹿一根胡萝卜，在池塘边坐下来钓一会儿鱼。

走得够远，草原会慢慢变成秋天的树林、粉色的樱花林、落雪的松林、结冰的湖，或者一望无际的沙漠。

<div align="center">

<!-- 截图放在 docs/screenshots/ 下，文件名对上即可显示 -->
<img src="docs/screenshots/meadow.png" alt="草原" width="49%"> <img src="docs/screenshots/snow.png" alt="雪原" width="49%">
<img src="docs/screenshots/sakura.png" alt="樱花林" width="49%"> <img src="docs/screenshots/night.png" alt="夜晚" width="49%">

</div>

## 特色

- 🌾 **无限草原**：每个种子都是一片新的世界，大平原、缓坡丘陵、远处的山脉
- 🍂 **六种群系**：草原 / 秋林 / 樱花林 / 雪原 / 冰原 / 沙漠，各有自己的植被、地面、天气和声音
- 🌅 **昼夜循环**：日出、正午、黄昏、星空，萤火虫在夜里亮起
- 🐰 **会交朋友的小动物**：兔子、小鹿、小鸟。摸一摸、喂一喂，它们会跟着你走一段路
- 🎣 **悠闲的小事**：捕蝴蝶、钓鱼、在雪地里留下一串脚印、看自己呼出的白气
- 👀 **会说话的眼睛**：主角没有嘴巴，十几种表情全靠一双大眼睛
- 🗺️ **探索迷雾**：走过的地方才会在地图上亮起来
- 🎧 **真实的自然声景**：风、树叶、鸟鸣、虫声、溪水，随时间和群系平滑过渡

## 操作

| 按键 | 动作 |
|---|---|
| `W` `A` `S` `D` / 方向键 | 移动 |
| 鼠标 | 转动视角 |
| `Shift` | 奔跑 |
| `Space` | 跳跃 |
| `E` | 互动（摸摸 / 喂食） |
| `1` – `4` | 切换手中的道具 |
| `B` | 背包 |
| `M` | 大地图 |
| `V` | 切换第一 / 第三人称 |
| 滚轮 | 镜头远近 |
| `T`（按住） | 时间快进 |
| `F11` | 全屏 |
| `Esc` | 暂停 / 设置 |

## 运行

1. 安装 [Godot 4.7](https://godotengine.org/download)（标准版，非 .NET）
2. 克隆仓库，在 Godot 中导入 `project.godot`
3. 按 `F5` 运行

导出：`项目 → 导出 → Windows Desktop`，产物放在 `build/`（已被 git 忽略）。

## 项目结构

```
scripts/      游戏逻辑（世界生成、角色、动物、UI、声音……）
shaders/      着色器（草、地形、天空、水、卡通渲染、描边、UI）
characters/   主角与动物模型
props/        手持道具模型
audio/        音效与环境声（来源见 audio/CREDITS.txt）
art/branding/ Logo 与图标
```

更详细的开发记录见 [`HANDOFF.md`](HANDOFF.md)。

## 制作

**xiaomao8090** —— 策划 · 美术 · 程序

## 致谢

- 环境声与脚步声：[BBC Sound Effects](https://sound-effects.bbcrewind.co.uk)（RemArc 许可，仅限个人使用）
- 引擎：[Godot Engine](https://godotengine.org)

## 许可

© 2026 xiaomao8090. 保留所有权利。

本仓库中的音频素材受 BBC RemArc 许可约束，**不得**用于商业用途或再分发。

<div align="center">
<sub>Made with 🌱 and a lot of wind.</sub>
</div>
