javascript:(function(next) {
    /**
     * This is bookmarklet that will create terminal with LIPS REPL
     *
     * Copyright (C) Jakub T. Jankiewicz <https://jcubic.pl/me>
     * Released under MIT license
     */
    if (window.jQuery) {
        return next(window.jQuery);
    }
    function attr(elem, key, value) {
        elem.setAttribute(document.createAttribute(key, value));
    }
    var script = (function() {
        var head = document.getElementsByTagName('head')[0];
        return function(src) {
            var script = document.createElement('script');
            script.setAttribute('src', src);
            script.setAttribute('type', 'text/javascript');
            head.appendChild(script);
            return script;
        };
    })();
    script('https://code.jquery.com/jquery-3.5.0.min.js');
    (function delay(time) {
        if (typeof jQuery == 'undefined') {
            setTimeout(delay, time);
        } else {
            next($.noConflict());
        }
    })(500);
})(async function($) {
    async function hash(branch) {
        try {
            var url = `https://api.github.com/repos/jcubic/lips/commits?sha=${branch}`;
            var res = await fetch(url);
            var data = await res.json();
            return data[0].sha;
        } catch(e) {
            return branch;
        }
    }
    const REF = await hash('master');
    function track() {
        /*
         * this is traking code using Matomo instance,
         * it don't save any personal information,
         * it's only used for statistics of usage.
         */
        try {
            var searchParams = new URLSearchParams({
                idsite: 7,
                rec: 1,
                action_name: 'bookmark',
                url: location.href
            });
            var url = new URL('https://piwik.jcubic.pl/matomo.php');
            url.search = searchParams.toString();
            var img = new Image();
            img.src = url.href;
        } catch (e) {}
    }
    function init() {
        var t = $('.terminal.lips');
        if (t.length) {
            t.each(function() {
                $(this).terminal().destroy().remove();
            });
        }
        $.terminal.defaults.linksNoReferrer = true;
        $.terminal.defaults.formatters = $.terminal.defaults.formatters.filter((x) => {
            return x.name !== 'syntax_scheme';
        });
        $.terminal.syntax("scheme");
        $('.shell-wrapper').remove();
        var wrapper = $('<div>').addClass('shell-wrapper').appendTo('body');
        var container = $('<div>').addClass('shell-container').appendTo(wrapper);
        var mask = $('<div class="shell-mask"/>').appendTo(wrapper);
        var nav = $('<nav/>').appendTo(container);
        var pos; $(document).off('mousemove');
        var height;
        $('nav').off('mousedown').mousedown(function(e) {
            height = container.height();
            pos = e.clientY;
            wrapper.addClass('drag');
            return false;
        });
        $(document).off('.terminal').on('mousemove.terminal', function(e) {
            if (pos) {
                container.height(height + (pos - e.clientY));
            }
        }).on('mouseup.terminal', function() {
            pos = null;
            wrapper.removeClass('drag');
        });
        $('<span class="shell-destroy">[x]</span>').click(function() {
            term.destroy();
            wrapper.remove();
        }).appendTo(nav);
        var term = terminal({ selector: $('<div class="lips">').appendTo(container), name: 'lips', lips });
        if (typeof lips.env.get('write', { throwError: false }) === 'undefined') {
            var path = `https://cdn.jsdelivr.net/gh/jcubic/lips@${REF}/`;
            term.exec([
                '(let ((e lips.env.__parent__))',
                  '(load "' + path + 'lib/bootstrap.scm" e)',
                  '(load "' + path + 'lib/R5RS.scm" e)',
                  '(load "' + path + 'lib/R7RS.scm" e))'
            ].join('\n'), true);
        }
        function format_baner(banner) {
            return banner.replace(/^[\s\S]+(LIPS.*\nCopy.*\n)[\s\S]*/, '$1')
                .replace(/(Jakub T. Jankiewicz)/, '[[!;;;;https://jcubic.pl/me]$1]');
        }
        term.echo(format_baner(lips.banner), {formatters: false});
        track();
        $('style.terminal').remove();
        $('<style class="terminal">.terminal.lips { font-size-adjust: none; --size: 1.2;height: calc(100% - 26px); } .shell-wrapper nav {cursor: row-resize; color:#ccc;border-bottom:1px solid #ccc;font-family:monospace;text-align: right;background:black; font-size:13px;line-height:initial;line-height: initial;margin: 0;width: 100%;height: auto;} .shell-container {position: fixed;z-index:99999;bottom:0;left:0;right:0;height:150px; }.shell-destroy {padding: 5px;cursor:pointer;display: inline-block;} .shell-wrapper .shell-mask{position:fixed;top:0;bottom:0;left:0;right:0;display:none; z-index: 100} .shell-wrapper.drag .shell-mask { display: block;</style>').appendTo('head');
    }
    ['https://unpkg.com/jquery.terminal/css/jquery.terminal.min.css',
     'https://cdn.jsdelivr.net/gh/jcubic/terminal-prism/css/prism-coy.css'
    ].forEach(function(url) {
        if (!$('link[href="' + url + '"]').length) {
            var link = $('<link href="' + url + '" rel="stylesheet"/>');
            var head = $('head');
            if (head.length) {
                link.appendTo(head);
            } else {
                link.appendTo('body');
            }
           }
    });
    if (typeof terminal !== 'undefined') {
        init();
    } else {
        var scripts = [
            'https://cdn.jsdelivr.net/npm/prismjs/prism.js',
            [
                'https://cdn.jsdelivr.net/combine/npm/jquery.terminal',
                'npm/jquery.terminal/js/prism.js',
                'npm/prismjs/components/prism-scheme.min.js',
                `gh/jcubic/lips@${REF}/lib/js/terminal.js`,
                `gh/jcubic/lips@${REF}/lib/js/prism.js`,
                'npm/js-polyfills/keyboard.js'
            ].join(','),
        ];
        (function recur() {
            var script = scripts.shift();
            if (!script) {
                if (window.lips) {
                    init();
                } else {
                    $.getScript(`https://cdn.jsdelivr.net/gh/jcubic/lips@${REF}/dist/lips.js`, init);
                }
            } else if (script.match(/prism.js$/) && typeof Prism !== 'undefined') {
                recur();
            } else {
                $.getScript(script, recur);
            }
        })();
    }
});
