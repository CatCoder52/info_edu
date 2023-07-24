(function($, global) {

	var openDelay = 500;
	var closeDelay = 250;
	var profileUrlPattern = new RegExp('^(?:' + window.location.protocol + '//' + window.location.host + ')?' + $.telligent.evolution.site.getBaseUrl() + 'members/([^/]+)(/(?:default\\.aspx)?)?', 'i');

	function handleContentPeekMessages(context) {
		$.telligent.evolution.messaging.subscribe('contentPeek.show', function(data){
			if (context.enabledContentTypes[data.contentTypeId.replace(/-/gi,'')]) {
				$.telligent.evolution.contentPeek.show(data.element, {
					contentTypeId: data.contentTypeId,
					contentId: data.contentId,
				});
			}
		})
		$.telligent.evolution.messaging.subscribe('contentPeek.hide', function(data){
			$.telligent.evolution.contentPeek.hide(data.element);
		})
	}

	function getUser(profileUrl) {
		return $.telligent.evolution.get({
			url: jQuery.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/remoting/url/entities.json',
			data: {
				Url: profileUrl
			}
		});
	}

	function handleLegacyUserLinks(context) {

		$(document)
			.on('glowDelayedMouseEnter', '.internal-link.view-user-profile, .internal-link.view-profile, .avatar > a', openDelay, function(e) {
				var link = $(this);
				var url = link.attr('href');
				if(!link.attr('core_userhover') && profileUrlPattern.test(url)) {
					getUser(url).then(function(r){
						if (r && r.UrlInformation && r.UrlInformation.Entities && r.UrlInformation.Entities.length > 0) {
							var userEntities = r.UrlInformation.Entities.filter(function(e) {
								return e.TypeName == "User" && !e.Relationship
							});
							if (userEntities && userEntities.length > 0) {
								$.telligent.evolution.contentPeek.show(link.get(0), {
									contentTypeId: userEntities[0].ContentTypeId,
									contentId: userEntities[0].ContentId
								});
							}
						}
					});
				}
			})
			.on('glowDelayedMouseLeave', '.internal-link.view-user-profile, .internal-link.view-profile, .avatar > a', closeDelay, function(e) {
				if(profileUrlPattern.test($(this).attr('href'))) {
					$.telligent.evolution.contentPeek.hide(this);
				}
			});

	}

	var api = {
		register: function(context) {
			context.enabledContentTypes = {};
			(context.contentTypeIds || '').split(',').forEach(function(id) {
				context.enabledContentTypes[id.replace(/-/gi,'')] = true;
			})
			handleContentPeekMessages(context);
			if (context.includeLegacyUserLinks)
				handleLegacyUserLinks(context);
		}
	};

	$.telligent = $.telligent || {};
	$.telligent.evolution = $.telligent.evolution || {};
	$.telligent.evolution.widgets = $.telligent.evolution.widgets || {};
	$.telligent.evolution.widgets.contentPeek = api;

}(jQuery, window));