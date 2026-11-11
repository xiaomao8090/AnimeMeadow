// 玩家碰到草/花时的倒伏：草叶绕着根部弯下去（长度不变），而不是把顶点往外推（那样会被拉长，看着像放大）
// pushers 由 world.gd 每帧设置：[0] 是玩家脚下（w = 0，一直压着），其余是刚走过的脚印（w = 离开后过了几秒）
// 脚离开后草不是匀速立起来，而是像弹簧一样：先弹起一大半、来回晃几下、再慢慢完全立直
const int PUSH_COUNT = 24;      // 要和 world.gd 的 PUSH_N 一致
uniform vec4 pushers[24];       // xyz = 脚的位置, w = 松开后经过的时间（秒）

const float PUSH_INNER = 0.28;  // 这个半径内完全压倒
const float PUSH_OUTER = 0.95;  // 到这个半径影响消失
const float PUSH_SLOW = 1.5;    // 慢慢立直的速度（越大恢复越快）
const float PUSH_WOBBLE = 0.45; // 回弹里"来回晃"占的比例
const float PUSH_DAMP = 3.6;    // 晃动衰减的速度（越大晃的次数越少）

// 返回 xy = 倒伏方向（水平单位向量），z = 倒伏程度（-1..1，负数 = 回弹时晃过头，朝反方向歪）
vec3 push_bend(vec3 root) {
	// 每棵草的弹性不一样：晃动的快慢、起晃的时间都错开一点，不会整片草同步摆
	float rnd = fract(sin(dot(root.xz, vec2(12.9898, 78.233))) * 43758.5453);
	float freq = 7.0 + 5.0 * rnd;
	float lag = rnd * 0.12;

	vec2 acc = vec2(0.0);
	float num = 0.0;
	float den = 0.00001;
	for (int i = 0; i < PUSH_COUNT; i++) {
		vec4 q = pushers[i];
		if (q.w > 4.0) {
			continue;
		}
		vec2 to = root.xz - q.xz;
		float dist = length(to);
		float f = 1.0 - smoothstep(PUSH_INNER, PUSH_OUTER, dist);
		// 脚离地（跳起来）或者脚在草根下面很多时不算碰到
		f *= 1.0 - smoothstep(0.25, 0.7, q.y - root.y);
		f *= 1.0 - smoothstep(0.6, 1.4, root.y - q.y);
		if (f <= 0.0) {
			continue;
		}
		float t = max(q.w - lag, 0.0);
		float slow = exp(-PUSH_SLOW * t);
		// 弹簧响应：t = 0 时是 1 且速度为 0，所以脚刚离开的那一刻没有跳变
		float resp = (1.0 - PUSH_WOBBLE) * slow
			+ PUSH_WOBBLE * exp(-PUSH_DAMP * t) * (cos(freq * t) + PUSH_DAMP / freq * sin(freq * t));
		// 同一棵草被好几个脚印盖住时，以最近踩的那个为主，平滑过渡
		float w = f * slow;
		acc += to / max(dist, 0.001) * w;
		w = w * w * w;
		num += w * f * resp;
		den += w;
	}
	// 正好在路线中间的草，前后脚印的方向会互相抵消，给一个每棵草固定的随机方向
	acc += vec2(cos(rnd * 6.2831853), sin(rnd * 6.2831853)) * 0.1;
	return vec3(normalize(acc), num / den);
}

// 把顶点 v 绕着根部朝 pb.xy 方向弯下去。h = 顶点在叶片上的高度 0..1，越靠上弯得越多
vec3 push_apply(vec3 v, vec3 root, float h, vec3 pb, float max_angle) {
	float ang = pb.z * max_angle * (0.35 + 0.65 * h);
	vec3 o = v - root;
	float od = dot(o.xz, pb.xy);
	float c = cos(ang);
	float s = sin(ang);
	float nd = od * c + o.y * s;
	float ny = o.y * c - od * s;
	o.xz += pb.xy * (nd - od);
	o.y = max(ny, min(o.y, 0.03));
	return root + o;
}
