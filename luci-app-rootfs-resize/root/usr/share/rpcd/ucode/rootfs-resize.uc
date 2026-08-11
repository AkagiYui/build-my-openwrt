#!/usr/bin/env ucode
'use strict';
// rpcd ucode 后端：暴露 rootfsresize.status / rootfsresize.resize 两个 ubus 方法
// 内部调用 /usr/libexec/rootfs-resize.sh，把输出解析后返回
//
// 注意：ucode stdlib 的 fs 模块没有 exec/system，只有 popen（官方 luci sys.uc 同款用法）

import { popen } from 'fs';

function run(action) {
	// 注意：fs.popen 的第二个参数是 mode('r'/'w')，不是参数数组！
	// 之前 popen(cmd, [action]) 把数组当 mode 忽略，脚本收不到参数，
	// 默认执行了 status 而不是 resize。必须把参数拼进命令字符串。
	let p = popen('/usr/libexec/rootfs-resize.sh ' + action);
	let out = '';

	for (let line = p.read('line'); length(line); line = p.read('line'))
		out += line + '\n';

	p.close();

	// status: 输出为单行 JSON；resize: 前面是日志行、最后一行是 JSON
	let data = null;
	try {
		data = json(out);
	}
	catch (e) {
		let lines = split(out, '\n');
		for (let i = length(lines) - 1; i >= 0; i--) {
			let l = trim(lines[i]);
			if (!length(l))
				continue;
			try {
				data = json(l);
			}
			catch (e2) {}
			break;
		}
	}

	if (!data)
		data = { ok: false, error: 'unable to parse script output' };

	data.log = out;
	return data;
}

const methods = {
	status: {
		call: function() {
			return run('status');
		}
	},
	resize: {
		call: function() {
			return run('resize');
		}
	}
};

return { 'rootfsresize': methods };
