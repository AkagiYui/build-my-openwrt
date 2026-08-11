'use strict';
'require view';
'require rpc';
'require ui';

const callStatus = rpc.declare({ object: 'rootfsresize', method: 'status' });
const callResize = rpc.declare({ object: 'rootfsresize', method: 'resize' });

// luci-base 没有内置 L.formatBytes（tailscale 等 app 也是自己实现的）
function formatBytes(bytes) {
	bytes = parseInt(bytes, 10);
	if (isNaN(bytes) || bytes <= 0)
		return '-';
	var units = [ 'B', 'KiB', 'MiB', 'GiB', 'TiB' ], i = 0;
	while (bytes >= 1024 && i < units.length - 1)
		bytes /= 1024, i++;
	return bytes.toFixed(i ? 1 : 0) + ' ' + units[i];
}

return view.extend({
	load: function() {
		return Promise.all([ callStatus() ]);
	},

	runResize: function() {
		var self = this;
		return ui.showConfirm(
			_('确认扩容'),
			_('将把 overlay 所在分区扩展到整个磁盘，并在线扩容文件系统。操作期间请勿断电。')
		).then(function(ok) {
			if (!ok)
				return;
			ui.showLoading(_('扩容中...'));
			return callResize().finally(function() {
				ui.hideLoading();
			}).then(function(res) {
				if (res && res.log)
					ui.addNotification(null, E('pre', {}, res.log));
				if (res && !res.ok && res.error)
					ui.addNotification(null, E('div', { 'class': 'alert alert-danger' }, res.error));
				window.location.reload();
			});
		});
	},

	render: function(data) {
		var s = data[0] || {};
		var stat;

		if (!s.ok)
			stat = E('div', { 'class': 'alert alert-danger' }, [ _('检测失败: '), (s.error || '-') ]);
		else if (s.can_resize)
			stat = E('div', { 'class': 'alert alert-success' }, _('检测到磁盘可用空间，可以一键扩容。'));
		else
			stat = E('div', { 'class': 'alert alert-warning' }, s.message || _('无需扩容。'));

		var tbl = E('table', { 'class': 'table' }, [
			E('tr', [ E('td', {}, _('磁盘设备')), E('td', {}, s.disk || '-') ]),
			E('tr', [ E('td', {}, _('根分区')), E('td', {}, s.partdev || '-') ]),
			E('tr', [ E('td', {}, _('磁盘大小')), E('td', {}, formatBytes(s.disk_sectors * 512)) ]),
			E('tr', [ E('td', {}, _('分区大小')), E('td', {}, formatBytes(s.part_sectors * 512)) ]),
			E('tr', [ E('td', {}, _('overlay 文件系统')), E('td', {}, formatBytes(s.loop_sectors * 512)) ]),
			E('tr', [ E('td', {}, _('overlay 用量')), E('td', {}, formatBytes(s.ovl_used_kb * 1024) + ' / ' + formatBytes(s.ovl_size_kb * 1024)) ]),
		]);

		var btn = E('button', {
			'class': 'btn btn-primary',
			'click': L.bind(this.runResize, this),
			'disabled': (s.ok && s.can_resize) ? null : 'disabled'
		}, _('一键扩容'));

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', { 'class': 'cbi-title' }, _('Rootfs / Overlay 扩容')),
			E('div', { 'class': 'cbi-map-descr' }, _('检测并扩展 overlay 所在分区与文件系统，抽象自 PVE 部署流程，无需重启。')),
			stat,
			tbl,
			E('div', {}, btn)
		]);
	}
});
