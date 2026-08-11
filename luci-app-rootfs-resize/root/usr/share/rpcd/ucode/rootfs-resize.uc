#!/usr/bin/env ucode
'use strict';
// rpcd ucode 后端：暴露 rootfsresize.status / rootfsresize.resize 两个 ubus 方法
// 内部调用 /usr/libexec/rootfs-resize.sh，把输出 JSON 解析后返回

import { exec } from 'fs';

function run(action) {
	let res = exec('/usr/libexec/rootfs-resize.sh', [ action ]);
	let data = null;
	try {
		data = JSON.parse(res[1]);
	} catch (e) {
		data = { ok: false, error: 'unable to parse script output', stdout: res[1], stderr: res[2], rc: res[0] };
	}
	data.log = res[1];
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
