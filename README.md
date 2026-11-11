<div align="center">

<img src="art/branding/animemeadow-logo-v1.png" alt="AnimeMeadow" width="520">

一片走不到尽头的草原

![Engine](https://img.shields.io/badge/Godot-4.7-478CBF?logo=godotengine&logoColor=white)
![Platform](https://img.shields.io/badge/platform-Windows-0078D6)
![Status](https://img.shields.io/badge/status-in%20development-E8A33D)

</div>

## 关于游戏

AnimeMeadow 是一款卡通渲染风格的漫游游戏

没有任务也没有敌人 你是一个背着背包的小旅人 在一片随风起伏的草原上随便走走
早上听鸟叫 傍晚追蝴蝶 晚上看萤火虫 路上可以摸摸兔子 喂小鹿吃胡萝卜 也可以在池塘边坐下钓鱼

走得远了 草原会变成秋天的树林 樱花林 下雪的松林 结冰的湖 或者沙漠

<div align="center">

<img src="docs/screenshots/meadow.png" alt="草原" width="49%"> <img src="docs/screenshots/snow.png" alt="雪原" width="49%">
<img src="docs/screenshots/sakura.png" alt="樱花林" width="49%"> <img src="docs/screenshots/night.png" alt="夜晚" width="49%">

</div>

## 内容

- 随机生成的无限地图 每个种子都不一样
- 六种群系 草原 秋林 樱花林 雪原 冰原 沙漠
- 昼夜循环和天气 雪原的夜里有极光
- 兔子 小鹿 小鸟 摸过喂过之后会跟着你走
- 捕蝴蝶 钓鱼 雪地脚印 冬天呼白气
- 主角没有嘴巴 表情全靠眼睛
- 小地图和探索迷雾
- 风声 鸟叫 虫鸣 水声会跟着时间和地点变化

## 操作

| 按键 | 动作 |
|---|---|
| W A S D 或方向键 | 移动 |
| 鼠标 | 视角 |
| Shift | 跑 |
| 空格 | 跳 |
| E | 摸摸 喂食 |
| 1 到 4 | 换手里的东西 |
| B | 背包 |
| M | 大地图 |
| V | 第一人称和第三人称 |
| 滚轮 | 镜头远近 |
| 按住 T | 时间快进 |
| F11 | 全屏 |
| Esc | 暂停和设置 |

## 运行

用 Godot 4.7 打开 project.godot 然后按 F5

导出在 项目 > 导出 > Windows Desktop 输出到 build 文件夹

## 目录

```
scripts       游戏代码
shaders       着色器
characters    主角和动物模型
props         道具模型
audio         声音 来源见 audio/CREDITS.txt
art/branding  logo 和图标
```

开发记录在 [HANDOFF.md](HANDOFF.md)

## 作者

xiaomao8090

## 致谢

环境声和脚步声来自 [BBC Sound Effects](https://sound-effects.bbcrewind.co.uk) 按 RemArc 许可仅限个人使用

引擎 [Godot Engine](https://godotengine.org)

## 版权

© 2026 xiaomao8090 保留所有权利

音频素材不能商用也不能再分发
