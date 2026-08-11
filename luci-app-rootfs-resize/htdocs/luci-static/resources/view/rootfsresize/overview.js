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

function descRow(label, value, desc) {
	return E('tr', [
		E('td', { 'class': 'cbi-value-title' }, label),
		E('td', { 'class': 'cbi-value-field' }, value || '-'),
		E('td', { 'class': 'cbi-value-description' }, desc || '')
	]);
}

return view.extend({
	load: function() {
		return Promise.all([ callStatus() ]);
	},

	runResize: function() {
		// 注意：luci 没有 ui.showConfirm/showLoading（v1.1.0 曾用它导致点击即
		// TypeError、请求根本没发出）。确认框用官方 L.showModal + 按钮触发。
		L.showModal(_('Confirm resize'), [
			E('div', _('The partition backing /overlay will be extended to the full disk and the filesystem will be resized online. Do not power off during the operation.')),
			E('div', { 'class': 'right' }, [
				E('div', { 'class': 'btn', 'click': L.hideModal }, _('Cancel')),
				' ',
				E('div', { 'class': 'btn primary', 'click': function() {
					ui.hideModal();
					ui.addTimeLimitedNotification(_('Resizing...'), [], 10000, 'info');
					callResize().then(function(res) {
						if (res && res.log)
							ui.addNotification(null, E('pre', res.log));
						if (res && !res.ok && res.error)
							ui.addNotification(null, E('div', { 'class': 'alert alert-danger' }, _('Resize failed: ') + res.error));
						window.location.reload();
					}).catch(function(e) {
						ui.addNotification(null, E('div', { 'class': 'alert alert-danger' }, _('Resize failed: ') + (e.message || e)));
						window.location.reload();
					});
				}}, _('Resize now'))
			])
		]);
	},

	render: function(data) {
		var s = data[0] || {};
		var freeBytes = (s.free_sectors || 0) * 512;
		var stat;

		if (!s.ok)
			stat = E('div', { 'class': 'alert alert-danger' }, [ _('Detection failed: '), (s.error || '-') ]);
		else if (s.can_resize && freeBytes >= 1024 * 1024 * 1024)
			stat = E('div', { 'class': 'alert alert-success' }, _('Free disk space detected, one-click resize is available.'));
		else if (s.can_resize)
			stat = E('div', { 'class': 'alert alert-warning' },
				_('Only %s can be gained. For a meaningful expansion, enlarge the disk first in the hypervisor / disk management.').replace('%s', formatBytes(freeBytes)));
		else if (freeBytes <= 1024 * 1024)
			stat = E('div', { 'class': 'alert alert-danger' },
				_('The partition already fills the whole disk. Enlarge the disk first in the hypervisor / disk management.'));
		else
			stat = E('div', { 'class': 'alert alert-warning' },
				_('Too little resizable space (%s). Enlarge the disk first in the hypervisor / disk management.').replace('%s', formatBytes(freeBytes)));

		var tbl = E('table', { 'class': 'table' }, [
			E('tr', [ E('th', {}, _('Item')), E('th', {}, _('Value')), E('th', {}, _('Description')) ]),
			descRow(_('Disk device'), s.disk, _('Whole virtual disk containing the GPT partition table')),
			descRow(_('Root partition'), s.partdev, _('Partition holding /rom and /overlay')),
			descRow(_('Disk size'), formatBytes(s.disk_sectors * 512), _('Total physical disk capacity assigned to the VM')),
			descRow(_('Partition size'), formatBytes(s.part_sectors * 512), _('Currently used portion of the disk')),
			descRow(_('Overlay filesystem'), formatBytes(s.loop_sectors * 512), _('Actual size of the filesystem mounted on /overlay')),
			descRow(_('Overlay usage'), formatBytes(s.ovl_used_kb * 1024) + ' / ' + formatBytes(s.ovl_size_kb * 1024), _('Used / total capacity of /overlay')),
			descRow(_('Resizable space'), formatBytes(freeBytes), _('Space expected to be gained after one-click resize'))
		]);

		var btn = E('button', {
			'class': 'btn btn-primary',
			'click': L.bind(this.runResize, this),
			'disabled': (s.ok && s.can_resize) ? null : 'disabled'
		}, _('Resize now'));

		return E('div', { 'class': 'cbi-map' }, [
			E('h2', { 'class': 'cbi-title' }, _('Rootfs / Overlay Resize')),
			E('div', { 'class': 'cbi-map-descr' }, _('Detect and extend the partition and filesystem backing /overlay, abstracted from the PVE deployment workflow. No reboot required.')),
			stat,
			tbl,
			E('div', {}, btn)
		]);
	}
});
