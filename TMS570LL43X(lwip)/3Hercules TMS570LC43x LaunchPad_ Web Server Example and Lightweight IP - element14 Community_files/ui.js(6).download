(function($, global, undef) {

	var notificationId = '__keyboard_tip';

	function init(context) {
		if (context.initialized) {
			return;
		}

		context.env = context.env || {
			os: {
				ios: /(iphone|ipad|ipod)/i.test(context.userAgent),
				android: /android/i.test(context.userAgent),
				mac: /macintosh/i.test(context.userAgent),
				windows: /windows/i.test(context.userAgent),
				linux: /linux/i.test(context.userAgent)
			},
			browser: {
				firefox: /firefox/i.test(context.userAgent),
				safari: /safari/i.test(context.userAgent) && !(/chrome/i.test(context.userAgent)),
				chrome: /chrome/i.test(context.userAgent) && !(/edge/i.test(context.userAgent)),
				ie: /msie|trident/i.test(context.userAgent),
				edge: /edge/i.test(context.userAgent)
			}
		};

		context.listTemplate = $.telligent.evolution.template(context.templates.shortcuts);
		context.notificationTemplate = $.telligent.evolution.template(context.templates.notification);

		context.initialized = true;
	}

	function hideNotification(context) {
		global.clearTimeout(context.notificationHandle);
		$.telligent.evolution.notifications.hide(notificationId);
	}

	function showNotification(context) {
		init(context);

		$.telligent.evolution.notifications.show(context.notificationTemplate(context.env), {
			id: notificationId,
			transient: true
		});
	}

	function showShortcuts(context, e) {
		if (e.isInput && e.combination !== 'alt + k')
			return;

		if (context.shortcutsVisible)
			return;

		context.shortcutsVisible = true;

		init(context);

		var visibleShortcuts = ($.telligent.evolution.shortcuts.list({ scoped: true }) || []).filter(function(s) {
			return s.description && s.description.length > 0
		});

		if (!visibleShortcuts || visibleShortcuts.length <= 1)
			return;

		var templateData = $.extend({}, context.env, {
			shortcuts: visibleShortcuts
		});

		$.glowModal({
			title: context.text.shortcutsTitle,
			html: context.listTemplate(templateData),
			width: 550,
			height: '100%',
			onClose: function() {
				context.shortcutsVisible = false;
			}
		});

		return false;
	}

	var api = {
		register: function(context) {

			context.userAgent = global.navigator.userAgent;
			context.shortcutsVisible = false;

			$(document).on('keydown', function(e) {
				if (e.key == 'Meta' || e.key == 'Alt' || e.key == 'Control') {
					context.notificationHandle = global.setTimeout(function() {
						showNotification(context);
					}, 100);
				} else {
					hideNotification(context);
				}
			});

			$(document).on('keyup', function(e) {
				if (e.key == 'Meta' || e.key == 'Alt' || e.key == 'Control') {
					hideNotification(context);
				}
			});

			$(window).on('blur', function(){
				hideNotification(context);
			});

			$.telligent.evolution.shortcuts.register('alt + k', function(e) {
				return showShortcuts(context, e)
			}, {
				description: context.text.showShortcuts
			});

			$.telligent.evolution.messaging.subscribe('shortcuts.list', function(e) {
				return showShortcuts(context, e)
			});
		}
	};

	$.telligent = $.telligent || {};
	$.telligent.evolution = $.telligent.evolution || {};
	$.telligent.evolution.widgets = $.telligent.evolution.widgets || {};
	$.telligent.evolution.widgets.keyboardShortcuts = api;

}(jQuery, window));