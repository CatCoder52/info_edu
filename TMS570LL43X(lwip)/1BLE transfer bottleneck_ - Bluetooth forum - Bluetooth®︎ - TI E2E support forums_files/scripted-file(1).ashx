
(function(){
			var FlattenedReplies = /*

FlattenedReplies

Thread widget private alternative to $.fn.evolutionThreadedReplies for flattened views of a thread

*/
(function ($, global, undef) {

	var FlattenedRepliesVotersPopup = (function () {
		var defaults = {
			votersTemplate: '' +
				' <% if(voters && voters.length > 0) { %>' +
				' 	<% foreach(voters, function(voter) { %>' +
				' 		<li class="content-item">' +
				' 			<div class="full-post-header"></div>' +
				' 			<div class="full-post">' +
				' 				<span class="avatar">' +
				' 					<a href="<%: voter.profileUrl %>"  class="internal-link view-user-profile">' +
				' 						<% if(voter.avatarHtml) { %>' +
				' 							<%= voter.avatarHtml %>' +
				' 						<% } else { %>' +
				' 							<img src="<%: voter.avatarUrl %>" alt="" border="0" width="32" height="32" style="width:32px;height:32px" />' +
				' 						<% } %>' +
				' 					</a>' +
				' 				</span>' +
				' 				<span class="user-name">' +
				' 					<a href="<%: voter.profileUrl %>" class="internal-link view-user-profile"><%= voter.displayName %></a>' +
				' 				</span>' +
				' 			</div>' +
				' 			<div class="full-post-footer"></div>' +
				' 		</li>' +
				' 	<% }); %>' +
				' <% } else { %>' +
				' 	<li>' +
				' 		<span class="content"><%= noVotesText %></span>' +
				' 	</li>' +
				' <% } %>',
			votersPopupTemplate: '' +
				' <div class="who-likes-list"> ' +
				'     <div class="content-list-header"></div> ' +
				'     <ul class="content-list"><%= voters %></ul> ' +
				'     <div class="content-list-footer"></div> ' +
				'     <% if(hasMorePages) { %> ' +
				'         <a href="#" class="show-more"><%= showMoreText %></a>' +
				'     <% } %> ' +
				' </div> ',
			noVotesText: 'No Votes',
			delegatedSelector: '.votes .current',
			modalTitleText: '',
			modalShowMoreText: 'More',
			loadVoters: function (options) {}
		};

		var FlattenedRepliesVotersPopup = function (options) {
			var context = $.extend({}, defaults, options || {});

			var settings = $.extend({}, defaults, options || {}),
				votersTemplate = $.telligent.evolution.template.compile(settings.votersTemplate),
				votersPopupTemplate = $.telligent.evolution.template.compile(settings.votersPopupTemplate),
				getOptions = function (elm) {
					return $.telligent.evolution.ui.data($(elm));
				},
				getVoters = function (options, pageIndex, complete) {
					var req = context.loadVoters({
						replyId: options.replyid,
						pageIndex: pageIndex
					});
					req.then(function (response) {
						// get the resized image html of all the avatars within a batch
						$.telligent.evolution.batch(function () {
							$.each(response.Users, function (i, user) {
								$.telligent.evolution.get({
									url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/ui/image.json',
									data: {
										url: user.AvatarUrl,
										maxWidth: 32,
										maxHeight: 32,
										resizeMethod: 'ZoomAndCrop'
									}
								}).then(function (response) {
									user.userAvatarHtml = response.Html;
								});
							});
						}).then(function () {
							complete({
								voters: $.map(response.Users, function (user) {
									var voter = {
										displayName: user.DisplayName,
										profileUrl: user.ProfileUrl,
										avatarHtml: user.userAvatarHtml
									};
									return voter;
								}),
								hasMorePages: (((response.PageIndex + 1) * response.PageSize) < response.TotalCount)
							});
						});
					});
				},
				showPopup = function (data, elm) {
					var currentPageIndex = 0,
						votersContent = $(votersTemplate($.extend(data, {
							noVotesText: settings.noVotesText || defaults.noVotesText
						}))),
						queryOptions = getOptions(elm),
						votersPopup = $(votersPopupTemplate({
							voters: votersContent,
							hasMorePages: data.hasMorePages,
							showMoreText: settings.modalShowMoreText
						})),
						votersList = votersPopup.find('ul'),
						showMoreLink = votersPopup.find('.show-more');

					votersList.html(votersContent);
					showMoreLink.on('click', function (e) {
						e.preventDefault();
						currentPageIndex++;
						getVoters(queryOptions, currentPageIndex, function (data) {
							votersList.append(votersTemplate(data));
							if (data.hasMorePages) {
								showMoreLink.show();
							} else {
								showMoreLink.hide();
							}
							var height = votersList[0].scrollHeight;
							votersList.scrollTop(height);
						});
					});

					$.glowModal({
						title: settings.modalTitleText,
						html: votersPopup,
						width: 450,
						height: '100%'
					});
				},
				delegateEvents = function () {
					$(settings.containerSelector).on('click', settings.delegatedSelector, function (e) {
						e.preventDefault();
						var elm = $(this);
						var queryOptions = getOptions(elm);
						getVoters(queryOptions, 0, function (data) {
							showPopup(data, elm);
						});
						return false;
					});
				};

			return {
				// options
				//   container
				handleVoterPopupRequests: function (options) {
					$(options.container).on('click', settings.delegatedSelector, function (e) {
						e.preventDefault();
						var elm = $(this);
						var queryOptions = getOptions(elm);
						getVoters(queryOptions, 0, function (data) {
							showPopup(data, elm);
						});
						return false;
					});
				}
			};
		};

		return FlattenedRepliesVotersPopup;
	})();

	var messaging = $.telligent.evolution.messaging;

	var defaults = {
		containerSelector: 'ul.content-list.threaded',
		replySelector: 'li.threaded.content-item',
		newReplySelector: 'a.new-reply',
		submitReplySelector: 'a.submit-new-reply',
		cancelReplySelector: 'a.cancel-new-reply',
		renderedContentSelector: '.rendered-content',
		wrapper: null,
		replyFormTemplate: null,
		onEditorAppendTo: null,
		onEditorRemove: null,
		onEditorVal: null,
		onEditorFocus: null,
		onGetReply: null,
		highlightClassName: 'new',
		highlightTimeout: 4 * 1000
	};

	// attempts to find an existing rendered reply to use instead of adding a duplicate (for merging)
	function getExistingRenderedReply(context, container, replyId) {
		var existing = context.container.find('li.content-item[data-id="' + replyId + '"]').first();
		if (existing && existing.length) {
			return existing;
		}
		return null;
	};

	function showReplyForm(context, replyId) {
		hideReplyForms(context);

		var newReplyWrapper = null;
		var reply = getExistingRenderedReply(context, context.container, replyId);
		newReplyWrapper = reply.find('.newreply').first();

		if (!newReplyWrapper || newReplyWrapper.length == 0) {
			return;
		}

		// create reply form if there
		var newReplyForm = newReplyWrapper.find('.reply-form').first();
		if (newReplyForm.length == 0) {
			newReplyForm = $(context.replyFormTemplate({
				editingReplyId: null
			}));
			newReplyWrapper.append(newReplyForm);
		}

		// move editor to it, clear it and focus it
		context.onEditorAppendTo({
			container: newReplyForm.find('.editor').first()
		});
		context.onEditorFocus();
	}

	function renderEdit(context, options) {
		var renderedReply = getExistingRenderedReply(context, context.container, options.replyId);
		if (renderedReply && renderedReply.length > 0) {
			renderedReply.addClass('hide-content').addClass('edit');
			hideReplyForms(context);


			var editReplyWrapper = renderedReply.find('.edit-form').first();
			var replyForm = editReplyWrapper.find('.reply-form').first();
			if (replyForm.length == 0) {
				replyForm = $(context.replyFormTemplate({
					editingReplyId: options.replyId,
					IsApproved: options.reply.isApproved
				}));
				editReplyWrapper.append(replyForm);
			}

			// move editor to it, clear it and focus it
			context.onEditorAppendTo({
				container: replyForm.find('.editor').first()
			});
			context.onEditorVal({
				val: options.reply.rawBody,
				suggested: options.reply.status == 'suggested'
			});
			context.onEditorFocus();
			$(".rendered-content.verified .editor .suggest-field .suggest").prop('checked', true);
			$(".rendered-content.verified .editor .suggest-field .suggest").prop('disabled', true);
		}
	}

	function hideReplyForms(context) {
		context.onEditorRemove();

		context.container.find('.reply-form').each(function () {
			var form = $(this);
			form.closest('.threaded.content-item').removeClass('hide-content').removeClass('edit');
		}).remove();

		var newReplyLink = context.wrapper.find(context.newReplySelector);
		if (newReplyLink.data('label-reply')) {
			newReplyLink.html(newReplyLink.data('label-reply'));
		}
	}

	function indicateTyping(context, options) {
		// get the existing parent reply to render the indicator alongside
		var existingReply = getExistingRenderedReply(context, context.container, options.parentId);
		if (existingReply !== null) {
			var typingStatusWrapper = existingReply.find('.typing-status-wrapper').first();
			if (options.typing) {
				typingStatusWrapper.empty().append(context.typingIndicatorTemplate({
					displayName: options.authorDisplayName
				}));
			} else {
				typingStatusWrapper.empty();
			}
			// indicate typing of new root reply
		} else {
			var typingStatusWrapper = context.wrapper.find('.typing-status-wrapper').first();
			if (options.typing) {
				typingStatusWrapper.empty().append(context.typingIndicatorTemplate({
					displayName: options.authorDisplayName
				}));
			} else {
				typingStatusWrapper.empty();
			}
		}
	}

	function getReplyItem(context, replyId) {
		return context.wrapper.find('.content-list.threaded .threaded.content-item[data-id="' + replyId + '"]');
	}

	function isOnLastPage(context) {
		var nextPageLink = context.wrapper.find('.pager .next');
		return nextPageLink.length == 0 || nextPageLink.is('.disabled');
	}

	function renderReply(context, reply) {
		return context.replyTemplate(reply);
	}

	function appendReply(context, reply) {
		var renderedReply = renderReply(context, reply);
		var listContainer = context.wrapper.find('.threaded-wrapper .content-list.threaded');
		listContainer.append(renderedReply)
	}

	function highlight(context, replyId, className) {
		className = className || 'new';
		context.wrapper.find('.content-list.threaded .threaded.content-item.permalinked').removeClass(className);
		var replyItem = getReplyItem(context, replyId);
		replyItem.addClass(className);
		setTimeout(function () {
			replyItem.removeClass(className);
		}, context.highlightTimeout);
	}

	function isFullyVisible (container, item, padding) {
		padding = padding || 0;

		if (container == document || (container instanceof jQuery && (container.get(0) == document || container.is('body')))) {
			var bound = (item instanceof jQuery) ? item.get(0).getBoundingClientRect() : item.getBoundingClientRect();
			return (
				(bound.top - padding) > 0 &&
				(bound.top + padding) <= (global.innerHeight || document.documentElement.clientHeight) &&
				(bound.bottom - padding) > 0 &&
				(bound.bottom + padding) <= (global.innerHeight || document.documentElement.clientHeight)
			);
		} else {
			container = $(container);

			var itemTop = item.offset().top;
			var itemBottom = itemTop + item.height();

			var containerTop = container.offset().top;
			var containerBottom = containerTop + container.height();

			return (
				((itemTop + padding) >= containerTop) &&
				((itemBottom - padding) <= containerBottom)
			);
		}
	}

	function scrollToElementIfNotVisible (container, item, padding, duration) {
		padding = padding || 0;
		duration = duration || 100;

		if (!isFullyVisible(container, item, padding)) {
			container = $(container);
			if (container.get(0) == document) {
				container = $('html, body');
			}
			container.stop().animate({
				scrollTop: item.offset().top - padding
			}, duration);
		}
	}

	function scrollTo(context, replyId) {
		var replyItem = getReplyItem(context, replyId);
		scrollToElementIfNotVisible($(document), replyItem, 200, 150);
	}

	function updateUrl(reply) {
		if (reply && reply.url) {
			history.pushState({}, "", reply.url);
		}
	}

	function navigateToLastPage(context) {
		return $.Deferred(function (d) {
			var navigatedSubscription = messaging.subscribe(context.pagedMessage, function () {
				messaging.unsubscribe(navigatedSubscription);
				d.resolve();
			});
			// navigate to last page via simply invoking ajax paging's own paging
			context.wrapper.find('.pager .ends a').last().trigger('click');
		}).promise();
	}

	function updateVotes(context, options) {
		var renderedReply = getExistingRenderedReply(context, context.container, options.replyId);
		if (renderedReply && renderedReply.length > 0) {
			var votes = renderedReply.find('.votes').first();

			// highlight currently-voted vote action
			if (options.value === true) {
				votes.find('a.vote').removeClass('selected');
				votes.find('.up').first().addClass('selected');
			} else if (options.value === false) {
				votes.find('a.vote').removeClass('selected');
				votes.find('.down').first().addClass('selected');
			} else if (options.value === null) {
				votes.find('a.vote').removeClass('selected');
			}

			// update current vote total for item
			if (options.yesVotes !== undef && options.noVotes !== undef) {
				var netVotes = options.yesVotes - options.noVotes;
				votes.find('.vote.current').html(netVotes > 0 ? '+' + netVotes : netVotes);
			}
		}
	}

	function buildVoterPopup(context) {
		context.voterPopup = new FlattenedRepliesVotersPopup({
			modalTitleText: context.text.peopleWhoVoted,
			modalShowMoreText: context.text.more,
			noVotesText: context.text.noVotes,
			loadVoters: function (options) {
				return context.onListVoters(options);
			}
		});
		context.voterPopup.handleVoterPopupRequests({
			container: context.container
		});
	}

	function handleEvents(context) {

		context.container.on('click', context.newReplySelector, function (e) {
			e.preventDefault();
			var target = $(e.target);

			// toggle reply form
			if (target.closest(context.replySelector).find('>.newreply .reply-form').length == 0) {
				showReplyForm(context, target.closest(context.replySelector).data('id'), true);
				// update the label if provided
				if (target.data('label-cancel')) {
					target.html(target.data('label-cancel'));
				}
			} else {
				hideReplyForms(context);
				// update the label if provided
				if (target.data('label-reply')) {
					target.html(target.data('label-reply'));
				}
			}

			return false;
		});
	}

	function handleMessages(context) {
		messaging.subscribe('ui.replies.edit.cancel', function (data) {
			hideReplyForms(context);
		});

		messaging.subscribe('ui.replies.edit', function (data) {
			var replyId = $(data.target).data('id');

			context.onGetReply({ replyId: replyId }).then(function (reply) {
				renderEdit(context, {
					replyId: replyId,
					reply: reply
				})
			});
		});

		messaging.subscribe('ui.replies.delete', function (data) {
			context.onPromptDelete($(data.target).data('id'))
		});

		messaging.subscribe('ui.replies.vote.message', function (data) {
			var target = $(data.target);
			if (target.hasClass('selected')) {
				context.onVoteReply({
					replyId: target.data('replyid'),
				}).then(function (v) {
					updateVotes(context, {
						value: null,
						replyId: v.replyId,
						yesVotes: v.yesVotes,
						noVotes: v.noVotes
					});
				});
			} else {
				context.onVoteReply({
					replyId: target.data('replyid'),
					value: target.data('value')
				}).then(function (v) {
					updateVotes(context, {
						replyId: v.replyId,
						value: target.data('value'),
						yesVotes: v.yesVotes,
						noVotes: v.noVotes
					});
				});
			}
		});
	}

	function debounce(fn, limit, onInitialBlockedAttempt) {
		var bounceTimout;
		return function () {
			var scope = this,
				args = arguments;
			if (onInitialBlockedAttempt && !bounceTimout) {
				onInitialBlockedAttempt.apply(scope, args);
			}
			clearTimeout(bounceTimout);
			bounceTimout = null;
			bounceTimout = setTimeout(function () {
				fn.apply(scope, args);
				clearTimeout(bounceTimout);
				bounceTimout = null;
			}, limit || 10);
		}
	}

	function requestAnimationFrameThrottle(fn) {
		if (!window.requestAnimationFrame)
			return fn;
		var timeout;
		return function () {
			var self, args = arguments;
			if (timeout)
				window.cancelAnimationFrame(timeout);
			var run = function() {
				fn.apply(self, args);
			}
			timeout = window.requestAnimationFrame(run);
		};
	}

	function FlattenedReplies(options) {
		this.context = $.extend({}, defaults, options || {});
	}

	FlattenedReplies.prototype.render = function (container) {
		var context = this.context;

		context.container = container;

		context.replyFormTemplate = $.telligent.evolution.template(context.replyFormTemplate);
		context.replyTemplate = $.telligent.evolution.template(context.replyTemplate);
		context.typingIndicatorTemplate = $.telligent.evolution.template(context.typingIndicatorTemplate);

		handleEvents(context);
		handleMessages(context);
		buildVoterPopup(context);

		context.container.show();
		if (context.replyId) {
			scrollTo(context, context.replyId);
		}

		// pre-focusing
		setTimeout(function () {
			// attempt to wait long enough to show pre-focused reply form after
			// logging in from anonymous, but can't be directly detected
			try {
				var query = $.telligent.evolution.url.parseQuery(global.location.href);
				if (query && query.focus) {
					showReplyForm(context, context.replyId);
				}
			} catch (e) {}
		}, 150);

		// schedule highlighted items to have their highlights removed once scrolled into view or paged
		context.scheduleHighlightRemovals = debounce(function () {
			context.container.find('li.content-item.' + context.highlightClassName).each(function () {
				var highlightedItem = $(this);
				if (highlightedItem.data('_unhighlighting')) {
					return;
				}
				highlightedItem.data('_unhighlighting', true);

				global.setTimeout(function () {
					highlightedItem.removeClass(context.highlightClassName);
				}, context.highlightTimeout);
			});
		}, 250);

		// highlight removal scheduling on debounced scroll
		$(global).on('scroll', requestAnimationFrameThrottle(function () {
			context.scheduleHighlightRemovals();
		}));
		// and on paging...
		messaging.subscribe(context.pagedMessage, function () {
			context.scheduleHighlightRemovals();
		});
		// and on init
		context.scheduleHighlightRemovals();
	};

	FlattenedReplies.prototype.replyCreated = function (options) {
		var context = this.context;
		context.onGetReply(options).then(function (reply) {
			if (reply.parentId) {
				indicateTyping(context, {
					typing: false,
					parentId: reply.parentId,
					authorDisplayName: ''
				});
			}
			if (options.isAuthor) {
				// render new reply and adjust current URL to permalink of new reply
				if (isOnLastPage(context)) {
					appendReply(context, reply);
					highlight(context, options.replyId, 'permalinked');
					scrollTo(context, options.replyId);
					updateUrl(reply);
				} else {
					// on a permalink, so natively navigate to the new reply's permalink URL
					if (context.replyId) {
						global.location.href = reply.url;
					} else {
						// on an organic page of replies, so just ajax page to end and adjust current URL to permalink
						navigateToLastPage(context).then(function () {
							highlight(context, options.replyId, 'permalinked');
							scrollTo(context, options.replyId);
							updateUrl(reply);
						});
					}
				}
			} else {
				if (isOnLastPage(context)) {
					appendReply(context, reply);
					highlight(context, options.replyId);
				} else {
					// rely on notifications
				}
			}
		});
	};

	FlattenedReplies.prototype.hideReplyForms = function () {
		this.context.onEditorRemove();

		this.context.container.find('.reply-form').each(function () {
			var form = $(this);
			form.closest('.threaded.content-item').removeClass('hide-content').removeClass('edit');
		}).remove();

		var newReplyLink = this.context.wrapper.find(this.context.newReplySelector);
		if (newReplyLink.data('label-reply')) {
			newReplyLink.html(newReplyLink.data('label-reply'));
		}
	};

	FlattenedReplies.prototype.updateReply = function (replyId, options) {
		// then re-load the reply
		var context = this.context;
		context.onGetReply({ replyId: replyId }).then(function (reply) {
			if (reply.isApproved === false)
				return;

			// and re-render it with a highlight
			var existingRenderedReply = getExistingRenderedReply(context, context.container, replyId);
			var newRenderedReply = renderReply(context, reply);
			if (existingRenderedReply)
				existingRenderedReply.replaceWith(newRenderedReply);

			if (options && options.highlight)
				highlight(context, replyId);
		});
	};

	FlattenedReplies.prototype.updateVotes = function (options) {
		var context = this.context;
		updateVotes(context, options);
	}

	FlattenedReplies.prototype.indicateTyping = function (data) {
		var context = this.context;

		// ignore messages from self
		if (data && data.authorId == $.telligent.evolution.user.accessing.id)
			return;

		// raise start typing
		indicateTyping(context, {
			typing: true,
			parentId: data.parentId,
			authorDisplayName: data.authorDisplayName
		});

		// raise stop typing after delay
		context.typingTimeouts = context.typingTimeouts || {};
		global.clearTimeout(context.typingTimeouts[data.parentId]);
		delete context.typingTimeouts[data.parentId];
		context.typingTimeouts[data.parentId] = global.setTimeout(function () {
			indicateTyping(context, {
				typing: false,
				parentId: data.parentId,
				authorDisplayName: data.authorDisplayName
			});
		}, data.delay * 1.5);
	}

	return FlattenedReplies;

})(jQuery, window);;
		(function ($, global, undef) {

	if (!$.telligent) {
		$.telligent = {};
	}
	if (!$.telligent.evolution) {
		$.telligent.evolution = {};
	}
	if (!$.telligent.evolution.widgets) {
		$.telligent.evolution.widgets = {};
	}

	var messaging = $.telligent.evolution.messaging;

	var model = {
	    endorseAnswer: function (context, forumId, threadId, replyId){
	      return $.telligent.evolution.post({
	         url: context.endorse,
	         data: {
	             replyId: replyId
	         }
	      });
	    },
	    updateResolutionStatus: function(context, threadId){
	      const resolutionStatus = $.telligent.evolution.post({
	         url: context.resolutionStatus,
	         data: {
	             threadId: threadId
	         }
	      });
	      updateResolutionStatus(context, resolutionStatus);
	    },
		unlinkWiki: function (context, threadId) {
			return $.telligent.evolution.post({
				url: context.unlinkUrl,
				data: {
					threadId: threadId
				}
			});
		},
		muteThread: function (context, threadId) {
			return $.telligent.evolution.post({
				url: context.muteUrl,
				data: {
					type: 'forumThread',
					mute: true,
					forumThreadId: threadId
				}
			});
		},
		unMuteThread: function (context, threadId) {
			return $.telligent.evolution.post({
				url: context.muteUrl,
				data: {
					type: 'forumThread',
					mute: false,
					forumThreadId: threadId
				}
			});
		},
		unSubscribeThread: function (context, threadId) {
			return $.telligent.evolution.post({
				url: context.subscribeUrl,
				data: {
					type: 'forumThread',
					subscribe: false,
					forumThreadId: threadId
				}
			});
		},
		subscribeThread: function (context, threadId) {
			return $.telligent.evolution.post({
				url: context.subscribeUrl,
				data: {
					type: 'forumThread',
					subscribe: true,
					forumThreadId: threadId
				}
			});
		},
		deleteThread: function (context, forumId, threadId) {
			var data = {
				ForumId: forumId,
				ThreadId: threadId,
				DeleteChildren: true,
				SendAuthorDeleteNotification: true,
				DeleteReason: "Deleted via UI"
			};
			return $.telligent.evolution.del({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/{ForumId}/threads/{ThreadId}.json',
				data: data
			});
		},
		voteThread: function (context, threadId) {
			return $.telligent.evolution.post({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/{ThreadId}/vote.json',
				data: {
					ThreadId: threadId
				}
			});
		},
		unvoteThread: function (context, threadId) {
			return $.telligent.evolution.del({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/{ThreadId}/vote.json',
				data: {
					ThreadId: threadId
				}
			});
		},
		getThreadVoteCount: function (context, threadId) {
			return $.telligent.evolution.get({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/{ThreadId}/votes.json',
				data: {
					ThreadId: threadId,
					PageSize: 1,
					PageIndex: 0
				}
			}).then(function (d) {
				return d.TotalCount;
			});
		},
		addReply: function (context, forumId, threadId, body, suggestAsAnswer, parentId) {
			var data = {
				ForumId: forumId,
				ThreadId: threadId,
				Body: body,
				SubscribeToThread: true,
				IsSuggestedAnswer: suggestAsAnswer
			};
			if (parentId) {
				data.ParentReplyId = parentId;
			}
		
			return $.telligent.evolution.post({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/{ForumId}/threads/{ThreadId}/replies.json',
				data: data
			});
		},
		updateReply: function (context, forumId, threadId, replyId, body, suggestAsAnswer) {
			return $.telligent.evolution.put({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/{ForumId}/threads/{ThreadId}/replies/{ReplyId}.json',
				data: {
					ForumId: forumId,
					ThreadId: threadId,
					ReplyId: replyId,
					Body: body,
					IsSuggestedAnswer: suggestAsAnswer
				}
			});
		},
		storeRootReplyToTempData: function (context, threadId, body, suggestAsAnswer) {
			return $.telligent.evolution.post({
				url: context.advancedReplyUrl,
				data: {
					threadId: threadId,
					replyBody: $.telligent.evolution.html.decode(body),
					isSuggestion: suggestAsAnswer
				}
			});
		},
		lockThread: function (context, forumId, threadId) {
		    global._tiAnalyticsTrack( 'Link Track', 'en_us_lock_e2e', global.tiPageName, global.tiContentGroup );
			return $.telligent.evolution.put({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/{ForumId}/threads/{ThreadId}.json',
				data: {
					ForumId: forumId,
					ThreadId: threadId,
					IsLocked: true
				}
			});
		},
		unlockThread: function (context, forumId, threadId) {
		    global._tiAnalyticsTrack( 'Link Track', 'en_us_unlock_e2e', global.tiPageName, global.tiContentGroup );
			return $.telligent.evolution.put({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/{ForumId}/threads/{ThreadId}.json',
				data: {
					ForumId: forumId,
					ThreadId: threadId,
					IsLocked: false
				}
			});
		},
		moderateUser: function (context, userId) {
			return $.telligent.evolution.put({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/users/{UserId}.json',
				data: {
					UserId: userId,
					ModerationLevel: 'Moderated'
				}
			});
		},
		unModerateUser: function (context, userId) {
			return $.telligent.evolution.put({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/users/{UserId}.json',
				data: {
					UserId: userId,
					ModerationLevel: 'Unmoderated'
				}
			});
		},
		voteReply: function (context, replyId, threadId) {
			// up-vote the quality of the reply along with voting up the answer/verification
			$.telligent.evolution.post({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/replies/{ReplyId}/vote.json',
				data: {
					ReplyId: replyId,
					VoteType: 'Quality',
					Value: true
				}
			});
			return $.telligent.evolution.post({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/replies/{ReplyId}/vote.json',
				data: {
					ReplyId: replyId
				}
			});
			
			//updateThreadStatus('Answered');
			//updateResolutionStatus(context, threadId);
			
			//return retVal;
		},
		unvoteReply: function (context, replyId, threadId) {
		    
			/*return $.telligent.evolution.del({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/replies/{ReplyId}/vote.json',
				data: {
					ReplyId: replyId
				}
			});*/
			return $.telligent.evolution.post({
				url: context.unvotereply,
				data: {
					threadId: threadId,
					replyId: replyId
				}
			});
			
			//updateThreadStatus('NotAnswered');
			//updateResolutionStatus(context, threadId);
			
			//return retVal;
		},
		getReply: function (context, replyId) {
			return $.telligent.evolution.get({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/replies/{ReplyId}.json',
				data: {
					ReplyId: replyId
				}
			});
		},
		getReplyVoteCount: function (context, replyId) {
			return $.telligent.evolution.get({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/replies/{ReplyId}/votes.json',
				data: {
					ReplyId: replyId,
					PageSize: 1,
					PageIndex: 0
				}
			}).then(function (d) {
				return d.TotalCount;
			});
		},
		storeReplyToTempData: function (context, options) {
			var data = {
				threadId: options.threadId,
				replyBody: $.telligent.evolution.html.decode(options.body),
				isSuggestion: options.suggestAsAnswer
			};

			if (options.parentReplyId)
				data.parentReplyId = options.parentReplyId;
			if (options.replyId)
				data.replyId = options.replyId;

			return $.telligent.evolution.post({
				url: context.advancedReplyUrl,
				data: data
			});
		},
		suggest: function (context, replyId, istier, threadId) {
			// up-vote the quality of the reply along with suggesting it as an answer
			$.telligent.evolution.post({
				url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/replies/{ReplyId}/vote.json',
				data: {
					ReplyId: replyId,
					VoteType: 'Quality',
					Value: true
				}
			});
			return $.telligent.evolution.post({
				url: context.editReplyUrl,
				data: prefix({
					replyId: replyId,
					suggestAnswer: true,
					isTier: istier
				})
			});
		},
		getBestReplies: function (context) {
			return $.telligent.evolution.get({
				url: context.listBestUrl
			});
		}
	};
	
	function updateResolutionStatus(context, status){
	    let statusHtml;
	    switch(status){
	        case 'Not Resolved':
	            statusHtml = '';
	            break;
            case 'Answer Suggested':
        		statusHtml = '<span class="attribute-value suggested">${context.resources.suggestedAnswer}</span>';
        		break;
        	case 'TI Thinks Resolved':
        		statusHtml = '<span class="attribute-value suggested">${context.resources.tiThinksResolved}</span>';
        		break;
        	case 'Resolved':
        		statusHtml = '<span class="attribute-value verified">${context.resources.resolved}</span>';
        		break;
        	default: return;
    	}
        	$( '.attribute-item.resolution-status' ).html( statusHtml );
    }
	
	function updateThreadStatus(status) {
    	let statusHtml;
    	switch(status) {
        	case 'Answered':
        		statusHtml = '<span class="attribute-value verified"><a href="#" data-messagename="telligent.evolution.widgets.thread.answerfilter" data-filter="answers" data-scroll="true">Answered</a></span>';
        		break;
        	case 'NotAnswered':
        		statusHtml = '<span class="attribute-value"><a href="#" data-messagename="telligent.evolution.widgets.thread.answerfilter" data-filter="answers" data-scroll="true">Not Answered</a></span>';
        		break;
        	case 'AnsweredNotVerified':
        		statusHtml = '<span class="attribute-value suggested"><a href="#" data-messagename="telligent.evolution.widgets.thread.answerfilter" data-filter="answers" data-scroll="true">Suggested Answer</a></span>';
        		break;
        	default: return;
    	}
    	$( '.attribute-item.answer-status' ).html( statusHtml );
	}
	
	function isTTOpen() {
    	return !!document.querySelector( '#dThreadDiv' );
    }
    
    //function setTrackActionCookie( threadId, replyId, action ) {
    //	const cookie = SystemJS.import( 'js-cookie' );
    //	cookie.set( 'track-action', { threadId: threadId, replyId: replyId, action: action }, { secure: location.protocol === 'https:' } );
    //}
	
	function loadMoreStartActions(context, options) {
		return $.telligent.evolution.get({
			url: context.moreStartActionsUrl,
			data: options
		});
	}

	function redirect(context, body) {
		$.telligent.evolution.post({
			url: context.redirect,
			data: {
				body: context.createEditor.val()
			}
		}).then(function (result) {
			var op = (context.loginUrl.indexOf('%3F') > 0) ? '%26' : '%3F';
			window.location = [context.loginUrl, result.tempKey].join(op);
		});
	}

	function validate(editor) {
		return $.trim(editor.val()).length > 0;
	}

	function createChildReply(context, body, forumId, threadId, parentId, suggestAnswer) {
		if (context.creating)
			return;
		context.creating = true;

		context.loadingIndicator = context.loadingIndicator || $('#' + context.wrapperId).find('.processing');
		context.loadingIndicator.removeClass('hidden');

		return model.addReply(context,
				forumId,
				threadId,
				body,
				suggestAnswer,
				parentId)
			.then(function (r) {
				context.replyEditor.checkedVal(false);
				context.replyEditor.val('');
				context.creating = false;
				context.loadingIndicator.addClass('hidden');

				if (!r.Reply.Approved) {
					$.telligent.evolution.notifications.show(context.replyModerated, {
						type: 'warning'
					});
				} else {
					$.telligent.evolution.notifications.show(context.successMessage, {
						duration: 3 * 1000
					});
				}

				$.telligent.evolution.messaging.publish('forumReply.created', {
					replyId: r.Reply.Id,
					threadId: r.Reply.ThreadId,
					approved: r.Reply.Approved,
					url: r.Reply.Url,
					parentId: r.Reply.ParentId,
					authorId: $.telligent.evolution.user.accessing.id,
					isAuthor: true,
					local: true
				});
				
				location.reload();
			})
			.catch(function () {
				context.creating = false;
				context.loadingIndicator.addClass('hidden');
			});
	}

	function createRootReply(context, body, forumId, threadId, suggestAnswer, position) {
		if (context.creating)
			return;
		context.creating = true;

		context.loadingIndicator = context.loadingIndicator || $('#' + context.wrapperId).find('.processing');
		context.loadingIndicator.removeClass('hidden');

		var editor = getCreateEditor(context, position);

		return model.addReply(context,
				forumId,
				threadId,
				body,
				suggestAnswer)
			.then(function (r) {

				editor.checkedVal(false);
				editor.val('');
				context.creating = false;
				context.loadingIndicator.addClass('hidden');

				if (!r.Reply.Approved) {
					$.telligent.evolution.notifications.show(context.replyModerated, {
						type: 'warning'
					});
				} else {
					$.telligent.evolution.notifications.show(context.successMessage, {
						duration: 3 * 1000
					});
				}

				$.telligent.evolution.messaging.publish('forumReply.created.root', {
					replyId: r.Reply.Id,
					threadId: r.Reply.ThreadId,
					approved: r.Reply.Approved,
					url: r.Reply.Url,
					authorId: $.telligent.evolution.user.accessing.id,
					isAuthor: true,
					local: true
				});
				
				location.reload();
			})
			.catch(function () {
				context.creating = false;
				context.loadingIndicator.addClass('hidden');
			});
	}

	function prefix(options) {
		var data = {};
		$.each(options, function (k, v) {
			data['_w_' + k] = v;
		});
		return data;
	}

	function throttle(fn, limit) {
		var lastRanAt, timeout;
		return function () {
			var scope = this,
				attemptAt = (new Date().getTime()),
				args = arguments;
			if (lastRanAt && (lastRanAt + (limit || 50)) > attemptAt) {
				global.clearTimeout(timeout);
				timeout = global.setTimeout(function () {
					lastRanAt = attemptAt;
					fn.apply(scope, args);
				}, (limit || 50));
			} else {
				lastRanAt = attemptAt;
				fn.apply(scope, args);
			}
		};
	}

	function handleEvents(context) {

		messaging.subscribe('telligent.evolution.widgets.thread.unlinkwiki', function (data) {
			var link = $(data.target);
			model.unlinkWiki(context, link.data('threadid')).then(function () {
				link.closest('.message').hide();
			});
		});

		messaging.subscribe('telligent.evolution.widgets.thread.mute', function (data) {
			var link = $(data.target);
			if (link.data('mute')) {
				link.html('...');
				model.unMuteThread(context, link.data('threadid')).then(function () {
					link.html(link.data('offtext')).data('mute', false);
					$('#' + link.data('links')).uilinks('hide');
				});
			} else {
				link.html('...');
				model.muteThread(context, link.data('threadid')).then(function () {
					link.html(link.data('ontext')).data('mute', true);
					$('#' + link.data('links')).uilinks('hide');
				});
			}
		});

		messaging.subscribe('telligent.evolution.widgets.thread.subscribe', function (data) {
			var link = $(data.target);
			if (link.data('subscribed')) {
				link.html('...');
				model.unSubscribeThread(context, link.data('threadid')).then(function () {
					link.html(link.data('offtext')).data('subscribed', false);
					$('#' + link.data('links')).uilinks('hide');
				});
			} else {
				link.html('...');
				model.subscribeThread(context, link.data('threadid')).then(function () {
					link.html(link.data('ontext')).data('subscribed', true);
					$('#' + link.data('links')).uilinks('hide');
				});
			}
		});

		messaging.subscribe('telligent.evolution.widgets.thread.deletethread', function (data) {
			var link = $(data.target);
			if (confirm(context.confirmDeleteThreadMessage)) {
				model.deleteThread(context,
						link.data('forumid'),
						link.data('threadid'))
					.then(function (data) {
						global.location = link.data('forumurl');
					});
			}
		});

		messaging.subscribe('telligent.evolution.widgets.thread.composereply', function (data) {
			var link = $(data.target);
			link.addClass('hidden');
			$('#' + link.data('cancelid')).removeClass('hidden');
			$('#' + link.data('replyformid')).removeClass('hidden').find('textarea').trigger('focus').trigger('focus');
			context.createEditor.focus();
		});

		messaging.subscribe('telligent.evolution.widgets.thread.cancelreply', function (data) {
			var link = $(data.target);
			link.addClass('hidden');
			$('#' + link.data('composeid')).removeClass('hidden');
			$('#' + link.data('replyformid')).addClass('hidden');
		});

		messaging.subscribe('telligent.evolution.widgets.thread.capture', function (data) {
			var link = $(data.target);
			Telligent_Modal.Open(link.data('captureurl'), 550, 300, null);
		});

		messaging.subscribe('telligent.evolution.widgets.thread.submit', function (data) {
			if (data.from != context.wrapperId + '-root')
				return;

			var editor = getCreateEditor(context, data.position);

			if (!validate(editor))
				return;

			var body = $.trim(editor.val());
			var suggestAnswer = editor.checkedVal();

			if (data.login) {
				redirect(context, body);
			} else {
				createRootReply(context, body, data.forumId, data.threadId, suggestAnswer, data.position);
			}
			
			// Sitecatalyst tracking
			_TrackSC( window.location, 'Reply to Existing Content' );
		});

		messaging.subscribe('telligent.evolution.widgets.thread.fullEditor.start', function (data) {
			var link = $(data.target);
			var suggestAnswer = context.createEditor.checkedVal();
			var body = context.createEditor.val();

			model.storeRootReplyToTempData(context,
					link.data('threadid'),
					body,
					suggestAnswer)
				.then(function (r) {
					global.location = r.replyUrl;
				});
		});

		messaging.subscribe(context.moreStartLinkMessage, function (e) {
			var moreLink = $(e.target);
			var links = moreLink.closest('.navigation-list');

			if (links.data('extra_links_loaded')) {
				links.uilinks('show', $(e.target));
			} else {
				links.data('extra_links_loaded', true);
				loadMoreStartActions(context, {
					forumApplicationId: moreLink.data('forumapplicationid'),
					threadContentId: moreLink.data('threadcontentid'),
					replyContentId: moreLink.data('replycontentid'),
					onAReplyPage: moreLink.data('onareplypage'),
					replyCount: moreLink.data('replycount'),
					replyPageIndex: moreLink.data('replypageindex'),
					postActionsId: moreLink.data('postactionsid')
				}).then(function (response) {
					$(response).children('li.navigation-list-item').each(function () {
						var cssClass = $(this).attr('class');
						var link = $(this).children('a, span').first();
						links.uilinks('add', link);
					});
					links.uilinks('show', moreLink);
				});
			}
		});

		messaging.subscribe('telligent.evolution.widgets.thread.typing', throttle(function (data) {
			if (data.from != context.wrapperId)
				return;

			sendTyping(context, {
				threadId: context.threadId
			});
		}, 1500));

		messaging.subscribe('telligent.evolution.widgets.thread.login', function (data) {
			var loginUrl = $.telligent.evolution.url.modify({
				url: context.loginUrl,
				query: {
					ReturnUrl: $.telligent.evolution.url.modify({
						url: $(data.target).data('replyurl'),
						query: {
							focus: 'true'
						}
					})
				}
			});
			global.location.href = loginUrl;
		});

		messaging.subscribe('ui-forumvote', function (data) {
			if (data.id == context.threadId && data.type == 'reply') {
				$(elm).html(data.count).attr('data-count', data.count);
				if (data.voted) {
					$(elm).attr('data-voted', 'true');
				} else {
					$(elm).attr('data-voted', 'false');
				}
			}
		});

		messaging.subscribe('ui-forumvote', function (data) {
			if (data.id != context.threadId)
				return;
			if (data.voted) {
				$(context.container).addClass('has-question');
			} else {
				$(context.container).removeClass('has-question');
			}
		});

		messaging.subscribe(context.moreLinkMessage, function (e) {
			var moreLink = $(e.target);
			var links = moreLink.closest('.navigation-list');

			if (links.data('extra_links_loaded')) {
				links.uilinks('show', $(e.target));
			} else {
				links.data('extra_links_loaded', true);
				loadMoreReplyActions(context, {
					forumApplicationId: moreLink.data('forumapplicationid'),
					threadContentId: moreLink.data('threadcontentid'),
					replyContentId: moreLink.data('replycontentid'),
					forumReplyActionsId: moreLink.data('forumreplyactionsid')
				}).then(function (response) {
					$(response).children('li.navigation-list-item').each(function () {
						var cssClass = $(this).attr('class');
						var link = $(this).children('a, span').first();
						links.uilinks('add', link);
					});
					links.uilinks('show', moreLink);
				});
			}
		});

		messaging.subscribe('telligent.evolution.widgets.thread.lock', function (data) {
			var link = $(data.target);
			if (link.data('locked')) {
				link.html('...');
				model.unlockThread(context, link.data('forumid'), link.data('threadid')).then(function () {
					link.html(link.data('offtext')).data('locked', false);
					$('#' + link.data('links')).uilinks('hide');
				});
			} else {
				link.html('...');
				model.lockThread(context, link.data('forumid'), link.data('threadid')).then(function () {
					link.html(link.data('ontext')).data('locked', true);
					$('#' + link.data('links')).uilinks('hide');
				});
			}
		});

		messaging.subscribe('telligent.evolution.widgets.thread.moderateuser', function (data) {
			var link = $(data.target);
			if (link.data('moderated')) {
				link.html('...');
				model.unModerateUser(context, link.data('userid')).then(function () {
					link.html(link.data('offtext')).data('moderated', false);
					$('#' + link.data('links')).uilinks('hide');
				});
			} else {
				link.html('...');
				model.moderateUser(context, link.data('userid')).then(function () {
					link.html(link.data('ontext')).data('moderated', true);
					$('#' + link.data('links')).uilinks('hide');
				});
			}
		});

		messaging.subscribe('telligent.evolution.widgets.thread.viewattachment', function (data) {
			var link = $(data.target);
			link.hide();
			link.closest('.attachment').find('.hide-attachment a').show().removeClass('hidden');
			link.closest('.attachment').find('.viewer').show().removeClass('hidden');
		});

		messaging.subscribe('telligent.evolution.widgets.thread.hideattachment', function (data) {
			var link = $(data.target);
			link.hide();
			link.closest('.attachment').find('.view-attachment a').show().removeClass('hidden');
			link.closest('.attachment').find('.viewer').hide().addClass('hidden');
		});

		messaging.subscribe('telligent.evolution.widgets.thread.votereply', function (data) {
			var link = $(data.target);
			model.voteReply(context, link.data('replyid'), link.data('threadid')).then(function (rep) {
				link.hide();
				$('#' + link.data('unvotelink')).show();
				model.getReplyVoteCount(context, link.data('replyid')).then(function (data) {
					messaging.publish('ui-forumvote', {
						type: 'reply',
						id: link.data('replyid'),
						count: data,
						voted: true
					});
					
					if(context.threadId == link.data('threadid')){
					    global._tiAnalyticsTrack( 'Link Track', 'votereply', global.tiPageName, global.tiContentGroup );
        			    location.reload();
        			}
				});
			});
		});
		
		messaging.subscribe('telligent.evolution.widgets.thread.auditTrail', function (data) {
    	    var link = $(data.target);
    	    $("#" + link.data('replyaudit') + "spin" ).removeClass('hidden');
            $.telligent.evolution.post({
				url: context.audittrail,
				data: {
				    forumId: context.forumId,
				    threadContentId:'',
                    replyContentId: link.data('replycontentid'),
  			    }
			}).then(function (response) {
			       	$("#" + link.data('replyaudit') + "spin" ).addClass('hidden');
			        $("#" + link.data('replyaudit')).html(response);
			});	
        });

        messaging.subscribe('telligent.evolution.widgets.thread.auditTrailthread', function (data) {
            debugger;
            	var link = $(data.target);
            $("#headauditspin").removeClass('hidden');
            $.telligent.evolution.post({
				url: context.audittrail,
				data: {
				    forumId: context.forumId,
				    threadContentId:link.data('threadcontentid'),
                    replyContentId: '',
  				}
			}).then(function (response) {
	            $("#headauditspin").addClass('hidden');
	            $("#headAudit").html(response);
			});	
        });

		messaging.subscribe('telligent.evolution.widgets.thread.unvotereply', function (data) {
			var link = $(data.target);
			model.unvoteReply(context, link.data('replyid'), link.data('threadid')).then(function (rep) {
				link.hide();
				$('#' + link.data('votelink')).show();
				model.getReplyVoteCount(context, link.data('replyid')).then(function (data) {
					messaging.publish('ui-forumvote', {
						type: 'reply',
						id: link.data('replyid'),
						count: data,
						voted: false
					});
					
					if(context.threadId == link.data('threadid')){
					    global._tiAnalyticsTrack( 'Link Track', 'unvotereply', global.tiPageName, global.tiContentGroup );
        			    location.reload();
        			}
				});
			});
		});

		messaging.subscribe('telligent.evolution.widgets.thread.fullEditor', function (data) {
			var replyForm = context.currentEditorParentContainer.closest('.reply-form');
			var replyOrParentId = replyForm.closest('.content-item').data('id');
			var isNew = replyForm.closest('.newreply').length > 0;

			//threadId, parentReplyId, body, suggestAsAnswer
			model.storeReplyToTempData(context, {
				threadId: context.threadId,
				parentReplyId: (isNew ? replyOrParentId : null),
				replyId: (isNew ? null : replyOrParentId),
				body: context.replyEditor.val(),
				suggestAsAnswer: context.replyEditor.checkedVal()
			}).then(function (r) {
				global.location = r.replyUrl;
			});
		});

		messaging.subscribe('telligent.evolution.widgets.thread.suggest', function (data) {
			var link = $(data.target);
			model.suggest(context, link.data('replyid'), link.data('istier'), link.data('threadid')).then(function (rep) {
			    //alert("loc 1");
				link.hide();
				if(context.threadId == link.data('threadid')){
				    global._tiAnalyticsTrack( 'Link Track', 'suggest', global.tiPageName, global.tiContentGroup );
    			    location.reload();
    			}
			});
		});
		
		messaging.subscribe('telligent.evolution.widgets.thread.endorseanswer', function (data) {
		   var link = $(data.target) ;
		   link.hide();
		   var forumId = link.data('forumid');
		   var threadId = link.data('threadid');
		   var replyId = link.data('replyid');
		   global._tiAnalyticsTrack( 'Link Track', 'endorseanswer', global.tiPageName, global.tiContentGroup );
		   model.endorseAnswer(context, forumId, threadId, replyId);
		});

		$(context.wrapper).on('click', '.content-item.thumbnail', function (e) {
			window.location = $(this).data('url');
		});

		$(context.wrapper).on('quote', '.content.full .content', function (e) {
			var c = $(e.target).closest('.content.full');
			var authorId = c.data('userid');
			var replyId = c.data('replyid');
			var threadId = c.data('threadid');
			var url = c.data('permalink');

			if (context.currentEditorParentContainer != null) {
				// has an open reply editor
				context.replyEditor.insert('[quote userid="' + (authorId || '') + '" url="' + (url || '') + '"]' + e.quotedHtml + '[/quote]');
				context.replyEditor.focus();
				return;
			}

			if (!$('#' + context.createWrapperId).hasClass('hidden')) {
				getCreateEditor(context, 'header').insert('[quote userid="' + (authorId || '') + '" url="' + (url || '') + '"]' + e.quotedHtml + '[/quote]');
				getCreateEditor(context, 'header').focus();
				return;
			}

			if (replyId) {
				var reply = $('.content-item[data-id="' + replyId + '"]');
				if (reply.length > 0) {
					reply.find('a.new-reply').first().trigger('click');
					global.setTimeout(function () {
						context.replyEditor.insert('[quote userid="' + (authorId || '') + '" url="' + (url || '') + '"]' + e.quotedHtml + '[/quote]');
						context.replyEditor.focus();
						return;
					}, 250);
					return;
				}
			}

			if (threadId) {
				var thread = $('.thread-start .content.full[data-threadid="' + threadId + '"]');
				if (thread.length > 0) {
					thread.find('.compose a').trigger('click');
					global.setTimeout(function () {
						getCreateEditor(context, 'header').insert('[quote userid="' + (authorId || '') + '" url="' + (url || '') + '"]' + e.quotedHtml + '[/quote]');
						getCreateEditor(context, 'header').focus();
						return;
					}, 250);
					return;
				}
			}
		});

		// when another user votes for a reply in the thread,
		// schedule a throttled update of best rplies
		var getBestDelayTimeout;
		var throttledLoadAndRenderBest = function () {
			// throttle reloading of best replies
			clearTimeout(getBestDelayTimeout);
			getBestDelayTimeout = setTimeout(function () {
				loadAndRenderBestReplies(context);
			}, 5 * 1000);
		}
		messaging.subscribe('forumReply.voted', function (data) {
			if (context.threadId == data.threadId) {
				throttledLoadAndRenderBest();
			}
		});
		messaging.subscribe('forumReply.updated', function (data) {
			if (context.threadId == data.threadId) {
				throttledLoadAndRenderBest();
			}
		});
		messaging.subscribe('forumReply.deleted', function (data) {
			if (context.threadId == data.threadId) {
				throttledLoadAndRenderBest();
			}
		});
		
		//for( var linkName of [ 'votereply', 'suggest', 'endorseanswer', 'unvotereply' ] ) {
		//    messaging.subscribe( `telligent.evolution.widgets.thread.${linkName}`, () => {
		//	    global._tiAnalyticsTrack( 'Link Track', linkName, global.tiPageName, global.tiContentGroup );
		//    } );
	    //}
	}

	function loadAndRenderBestReplies(context) {
		model.getBestReplies(context).then(function (r) {
			if (r && r.bestReplies) {
				$('#' + context.bestRepliesWrapperId).html(r.bestReplies);
			}
		});
	}

	function loadMoreReplyActions(context, options) {
		return $.telligent.evolution.get({
			url: context.moreActionsUrl,
			data: options
		});
	}

	function initCreateRootReplyForm(context) {
		if (context.tempBody && context.tempBody.length > 0) {
			setTimeout(function () {
				createRootReply(context, context.tempBody, context.forumId, context.threadId);
			}, 500);
		}
		context.createEditor.attachOnChange();
		if (context.footerCreateEditor)
			context.footerCreateEditor.attachOnChange();
	}

	function openDeletePanel(context, options) {
		var deleteForumReplyPanelUrl = context.deleteForumReplyPanelUrl.replace('replyid=0', 'replyid=' + options.replyId);
		global.location.href = deleteForumReplyPanelUrl;
	}

	function voteReply(context, options) {
		// vote up
		if (options.value === true) {
			return $.telligent.evolution.post({
				url: jQuery.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/replies/{ReplyId}/vote.json',
				data: {
					ReplyId: options.replyId,
					VoteType: 'Quality',
					Value: true
				}
			}).then(function (response) {
				loadAndRenderBestReplies(context);
				return {
					replyId: options.replyId,
					yesVotes: response.ForumReplyVote.Reply.QualityYesVotes,
					noVotes: response.ForumReplyVote.Reply.QualityNoVotes,
					value: true
				};
			});
			// vote down
		} else if (options.value === false) {
			return $.telligent.evolution.post({
				url: jQuery.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/replies/{ReplyId}/vote.json',
				data: {
					ReplyId: options.replyId,
					VoteType: 'Quality',
					Value: false
				}
			}).then(function (response) {
				loadAndRenderBestReplies(context);
				return {
					replyId: options.replyId,
					yesVotes: response.ForumReplyVote.Reply.QualityYesVotes,
					noVotes: response.ForumReplyVote.Reply.QualityNoVotes,
					value: false
				};
			});
			// delete vote
		} else {
			return $.telligent.evolution.del({
				url: jQuery.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/replies/{ReplyId}/vote.json',
				data: {
					ReplyId: options.replyId,
					VoteType: 'Quality'
				}
			}).then(function (response) {
				loadAndRenderBestReplies(context);
				return {
					replyId: options.replyId,
					value: null
				};
			});
		}
	}

	function sendTyping(context, options) {
		return $.telligent.evolution.sockets.forums.send('typing', {
			threadId: context.threadId,
			parentReplyId: options.parentId
		});
	}

	function getCreateEditor(context, position) {
		if (!context.footerCreateEditor)
			return context.createEditor;

		if (!position || position != 'header')
			return context.footerCreateEditor;

		return context.createEditor;
	}

	function listVoters(options) {
		return $.telligent.evolution.get({
			url: $.telligent.evolution.site.getBaseUrl() + 'api.ashx/v2/forums/threads/replies/{ReplyId}/votes.json',
			data: {
				ReplyId: options.replyId,
				VoteType: 'Quality',
				PageIndex: options.pageIndex
			},
			cache: false
		}).then(function (r) {
			var users = $.map(r.ForumReplyVotes, function (v) {
				return v.User
			});
			r.Users = users;
			return r;
		});
	}

	/*
		options:
			replyId
	*/
	function getReply(context, options) {
		return $.telligent.evolution.get({
			url: context.getReplyUrl,
			data: prefix(options)
		});
	}

	function initThreaded(context) {
		// prevent notifications about replies when in threaded mode, just scroll up and down to them or show indicator
		$.telligent.evolution.notifications.addFilter('e3df1b21-ac81-4eb3-8ab6-69dc049f5684');
		// init evolution threaded replies against the forum reply API
		$(context.wrapper).evolutionThreadedReplies({
			replyId: context.replyId,
			preFocus: context.preFocus,
			sortBy: context.sortBy,
			filter: context.filter,
			headerContent: $.telligent.evolution.template(context.headerTemplate)({}),
			sortOrder: context.sortOrder,
			flattenedSortBy: context.flattenedSortBy,
			flattenedSortOrder: context.flattenedSortOrder,
			replyOffsetId: context.replyOffsetId,
			replyOffsetDirection: context.replyOffsetDirection,
			threadUrl: context.threadUrl,
			onParseReplyId: function () {
				// parse the reply ID out of a thread URL
				var replyId = null;
				var urlParts = global.location.href.split(context.threadUrl);
				if (urlParts && urlParts.length > 0) {
					parsedIds = urlParts[urlParts.length - 1].match(/^\d+|\d+\b|\d+(?=\w)/g);
					if (parsedIds && parsedIds.length > 0) {
						replyId = parseInt(parsedIds[0]);
					}
				}
				return replyId;
			},
			onGenerateReplyUrl: function (id) {
				return context.threadUrl + '/' + id + '#' + id;
			},
			replySortByQueryStringKey: 'ReplySortBy',
			replySortOrderQueryStringKey: 'ReplySortOrder',
			replyFilterQueryStringKey: 'ReplyFilter',
			defaultReplyIdQueryStringValue: null,
			defaultReplySortByQueryStringValue: 'CreatedDate',
			defaultReplySortOrderQueryStringValue: 'Ascending',
			pageSize: context.pageSize,
			flattenedDepth: context.flattenedDepth,
			loadOnScroll: context.endlessScroll,
			wrapper: context.wrapper,
			container: context.container,
			text: context.text,
			includeFirstPageOnPermalinks: true,
			baseLoadIndicatorsOnSiblings: true,
			highlightNewReplySeconds: context.highlightNewSeconds,
			noRepliesMessage: context.noRepliesMessage,

			/*
			options:
				parentId // if by parent id, assumes to also get total reply count of parent
				replyId // if by reply id, assumes to also get reply and permalink context
				flattenedDepth
				sortBy
				sortOrder
				startReplyId
				endReplyId
			returns:
				nested list of replies
					potentialy including the reply's parents
					and the individual reply if specific
					and any of the reply's children
			*/
			onListReplies: function (options) {
				var listReplyQuery = {
					forumId: context.forumId,
					threadId: context.threadId,
					parentId: options.parentId || null,
					replyId: options.replyId || null,
					replyType: options.filter || null,
					includeSiblings: options.includeSiblings || false,
					flattenedDepth: (options.flattenedDepth === undef ? context.flattenedDepth : options.flattenedDepth),
					sortBy: options.sortBy || context.sortBy,
					sortOrder: options.sortOrder || context.sortOrder,
					flattenedSortBy: options.flattenedSortBy || context.flattenedSortBy,
					flattenedSortOrder: options.flattenedSortOrder || context.flattenedSortOrder,
					startReplyId: options.startReplyId || null,
					endReplyId: options.endReplyId || null,
					pageIndex: options.explicitPageIndex || null,
					initial: options.initial || false
				};
				if (context.lastReadDate) {
					listReplyQuery.threadLastReadDateOnLoad = context.lastReadDate;
				}

				return $.telligent.evolution.get({
					url: context.listRepliesUrl,
					data: prefix(listReplyQuery)
				});
			},
			/*
			options:
				replyId
				pageIndex
			*/
			onListVoters: listVoters,
			/*
			options:
				body
				parentId
			returns:
				promised reply
			*/
			onAddReply: function (options) {
				return $.telligent.evolution.post({
					url: context.addReplyUrl,
					data: prefix({
						forumId: context.forumId,
						threadId: context.threadId,
						parentId: options.parentId || null,
						body: options.body || null,
						suggestAnswer: options.data && options.data.suggestAnswer,
						subscribeToThread: true
					})
				})
				    .done(function() {
				        context.replyEditor.val('');
				    });
			},
			/*
			options:
				body
				replyId
			returns
				promised reply
			*/
			onEditReply: function (options) {
				return $.telligent.evolution.post({
					url: context.editReplyUrl,
					data: prefix({
						replyId: options.replyId || null,
						body: options.body || null,
						suggestAnswer: options.data && options.data.suggestAnswer
					})
				})
    				.done(function() {
				        context.replyEditor.val('');
				    });
			},
			/*
			options:
				replyId
			returns:
				promised reply
			*/
			onGetReply: function (options) {
				return getReply(context, options);
			},
			/*
			options:
				replyId
			*/
			onDeletePrompt: function (options) {
				openDeletePanel(context, options);
			},
			/*
			options:
				replyId
				value: true|false|null // up/down/delete
			Returns:
				reply
			*/
			onVoteReply: function (options) {
				return voteReply(context, options);
			},

			onTyping: function (options) {
				return sendTyping(context, options);
			},

			// raise callbacks on model
			onInit: function (controller) {
				$.telligent.evolution.messaging.subscribe('forumReply.updated', function (data) {
					if (context.threadId == data.threadId && data.approved) {
						controller.raiseReplyUpdated({
							threadId: data.threadId,
							forumId: data.forumId,
							replyId: data.replyId,
							authorId: data.authorId
						})
					}
				});
				$.telligent.evolution.messaging.subscribe('forumReply.created.root', function (data) {
					if (context.threadId == data.threadId && data.approved) {
						controller.raiseReplyCreated({
							replyId: data.replyId,
							forceRender: true
						})
					}
				});
				$.telligent.evolution.messaging.subscribe('forumReply.created', function (data) {
					if (context.threadId == data.threadId && data.approved) {
						controller.raiseReplyCreated({
							parentId: data.parentId,
							replyId: data.replyId,
							total: data.total,
							authorId: data.authorId
						})
					}
				});
				$.telligent.evolution.messaging.subscribe('forumReply.typing', function (data) {
					if (context.threadId == data.threadId) {
						controller.raiseTypingStart(data)
					}
				});
				$.telligent.evolution.messaging.subscribe('forumReply.voted', function (data) {
					if (context.threadId == data.threadId) {
						controller.raiseVote({
							replyId: data.replyId,
							yesVotes: data.yesVotes,
							noVotes: data.noVotes
						});
					}
				});
				$.telligent.evolution.messaging.subscribe('forumReply.deleted', function (data) {
					controller.raiseReplyDeleted({
						replyId: data.replyId,
						deleteChildren: data.childCount === 0
					});
				});
				$.telligent.evolution.messaging.subscribe('ui.forumReply.delete', function (data) {
					controller.attemptDelete({
						replyId: data.replyId,
						deleteChildren: data.deleteChildren
					});
				});
				$.telligent.evolution.messaging.subscribe('widgets.thread.typing', function (data) {
					controller.attemptTyping({
						parentId: data.container.closest('.content-item').data('id')
					})
				});
				$.telligent.evolution.messaging.subscribe('telligent.evolution.widgets.thread.submit', function (data) {
					if (data.from != context.wrapperId + '-nested')
						return;
					var replyForm = context.currentEditorParentContainer.closest('.reply-form');
					// editing existing reply
					if (replyForm.length > 0 && replyForm.data('editing')) {
						controller.attemptUpdate({
							body: context.replyEditor.val(),
							replyId: replyForm.data('editing'),
							data: {
								suggestAnswer: context.replyEditor.checkedVal()
							}
						})
						// adding new reply
					} else {
						controller.attemptCreate({
							parentId: context.currentEditorParentContainer.closest('.content-item').data('id'),
							body: context.replyEditor.val(),
							data: {
								suggestAnswer: context.replyEditor.checkedVal()
							}
						});
					}
				});
			},

			// adjust the filter UI as per current request
			onFilterChange: function (options) {
				$(context.filterWrapper).find('li').removeClass('selected').each(function () {
					var li = $(this);
					if (li.data('sortby') == options.sortBy && li.data('sortorder') == options.sortOrder) {
						li.addClass('selected');
					}
				});

				// only show sort options if not viewing answers tab
				if (options.filter == 'Answers') {
					$(context.filterWrapper).find('ul.order').hide();
				} else {
					$(context.filterWrapper).find('ul.order').show();
					// highlight the "All Answers" tab
					$(context.filterWrapper).find('ul.type li[data-sortby="CreatedDate"]').addClass('selected');
				}
			},

			/*
			container
			*/
			onEditorAppendTo: function (options) {
				context.currentEditorParentContainer = options.container;
				context.replyEditor.appendTo(options.container);
				context.replyEditor.checkedVal(false);
			},
			onEditorRemove: function (options) {
				context.currentEditorParentContainer = null;
				context.replyEditor.remove();
			},
			onEditorVal: function (options) {
				context.replyEditor.val(options.val);
				if (options.meta && options.meta.status == "suggested") {
					context.replyEditor.checkedVal(true);
				}
			},
			onEditorFocus: function (options) {
				context.replyEditor.focus();
			},

			// templates
			loadMoreTemplate: context.loadMoreTemplate,
			newRepliesTemplate: context.newRepliesTemplate,
			replyTemplate: context.replyTemplate,
			typingIndicatorTemplate: context.typingIndicatorTemplate,
			replyListTemplate: context.replyListTemplate,
			replyFormTemplate: context.replyFormTemplate
		});
	}

	function initFlattened(context) {

		context.flattenedReplies = new FlattenedReplies({
			wrapper: $(context.wrapper),
			replyFormTemplate: context.replyFormTemplate,
			replyTemplate: context.replyTemplate,
			typingIndicatorTemplate: context.typingIndicatorTemplate,
			highlightTimeout: context.highlightNewSeconds * 1000,
			pagedMessage: context.pagedMessage,
			replyId: context.replyId,
			text: context.text,
			onPromptDelete: function (replyId) {
				var deleteForumReplyPanelUrl = context.deleteForumReplyPanelUrl.replace('replyid=0', 'replyid=' + replyId);
				global.location.href = deleteForumReplyPanelUrl;
			},
			onGetReply: function (options) {
				return getReply(context, options);
			},
			onVoteReply: function (options) {
				return voteReply(context, options);
			},
			onListVoters: listVoters,
			onEditorAppendTo: function (options) {
				context.currentEditorParentContainer = options.container;
				context.replyEditor.appendTo(options.container);
				context.replyEditor.checkedVal(false);
			},
			onEditorRemove: function (options) {
				context.currentEditorParentContainer = null;
				context.replyEditor.remove();
			},
			onEditorVal: function (options) {
				context.replyEditor.val(options.val);
				if (options.suggested) {
					context.replyEditor.checkedVal(true);
				}
			},
			onEditorFocus: function (options) {
				context.replyEditor.focus();
			}
		});

		messaging.subscribe('forumReply.created.root', function (data) {
			if (context.threadId != data.threadId || !data.approved)
				return;
			if (data.authorId == $.telligent.evolution.user.accessing.id && !data.local)
				return;
			context.flattenedReplies.replyCreated(data);
		});

		messaging.subscribe('forumReply.created', function (data) {
			if (context.threadId != data.threadId || !data.approved)
				return;
			if (data.authorId == $.telligent.evolution.user.accessing.id && !data.local)
				return;
			context.flattenedReplies.replyCreated(data);
		});

		messaging.subscribe('forumReply.updated', function (data) {
			if (context.threadId != data.threadId || !data.approved)
				return;

			context.flattenedReplies.updateReply(data.replyId, {
				highlight: true
			});
		});

		messaging.subscribe('forumReply.voted', function (data) {
			context.flattenedReplies.updateVotes({
				replyId: data.replyId,
				yesVotes: data.yesVotes,
				noVotes: data.noVotes
			});
		});

		$.telligent.evolution.messaging.subscribe('forumReply.typing', function (data) {
			if (context.threadId != data.threadId)
				return;

			context.flattenedReplies.indicateTyping(data);
		});

		messaging.subscribe('telligent.evolution.widgets.thread.submit', function (data) {
			if (data.from != context.wrapperId + '-nested')
				return;

			var replyForm = context.currentEditorParentContainer.closest('.reply-form');

			// editing existing reply
			if (replyForm.length > 0 && replyForm.data('editing')) {
				var body = $.trim(context.replyEditor.val());
				var suggestAnswer = context.replyEditor.checkedVal();
				var replyId = replyForm.data('editing');

				model.updateReply(context, context.forumId, context.threadId, replyId, body, suggestAnswer).then(function (r) {
					if (!r.Reply.Approved)
						return;

					context.flattenedReplies.hideReplyForms();
				});
				// adding new reply
			} else {
				if ($.trim(context.replyEditor.val()).length <= 0)
					return;

				var body = $.trim(context.replyEditor.val());
				var suggestAnswer = context.replyEditor.checkedVal();
				var parentId = context.currentEditorParentContainer.closest('.content-item').data('id');

				if (data.login) {
					redirect(context, body);
				} else {
					createChildReply(context, body, context.forumId, context.threadId, parentId, suggestAnswer).then(function () {
						context.flattenedReplies.hideReplyForms();
					});
				}
			}
		});

		messaging.subscribe('widgets.thread.typing', throttle(function (data) {
			sendTyping(context, {
				parentId: data.container.closest('.content-item').data('id')
			});
		}, 1500));

		messaging.subscribe('ui.forumReply.delete', function (data) {
			$.telligent.evolution.notifications.show(context.text.deleted);
			global.location.href = context.threadUrl;
		});

		context.flattenedReplies.render($(context.container));
	}

	$.telligent.evolution.widgets.thread = {
		register: function (context) {
			initCreateRootReplyForm(context);
			handleEvents(context);

			if (context.flat)
				initFlattened(context);
			else
				initThreaded(context);
		}
	};

})(jQuery, window);
})();