(function () {
  var THEME_KEY = 'bm_theme';
  var LANG_KEY = 'bm_lang';
  var root = document.documentElement;
  var themeBtn = document.getElementById('bm-theme-toggle');
  var navBtn = document.getElementById('bm-nav-toggle');
  var navOverlay = document.getElementById('bm-nav-overlay');
  var sidebar = document.querySelector('.bm-sidebar');
  var langSelect = document.getElementById('bm-lang-select');
  var colorSchemeMql = null;
  var lang = (root.getAttribute('lang') || 'en').toLowerCase();
  var THEME_LABELS = {
    en: { light: 'Light', dark: 'Dark', auto: 'Auto' },
    zh: { light: '浅色', dark: '深色', auto: '自动' },
  };

  function getSystemPrefersDark() {
    if (!window.matchMedia) {
      return false;
    }
    try {
      if (!colorSchemeMql) {
        colorSchemeMql = window.matchMedia('(prefers-color-scheme: dark)');
      }
      return !!(colorSchemeMql && colorSchemeMql.matches);
    } catch (e) {
      return false;
    }
  }

  function closeNav() {
    document.body.classList.remove('bm-nav-open');
  }

  function toggleNav() {
    document.body.classList.toggle('bm-nav-open');
  }

  function applyTheme(themeMode) {
    if (!themeMode) themeMode = 'auto';

    // Remember the logical mode (light / dark / auto)
    root.dataset.themeMode = themeMode;

    // Resolve the effective theme used for styling
    var effective = themeMode;
    if (themeMode === 'auto') {
      effective = getSystemPrefersDark() ? 'dark' : 'light';
    }

    root.dataset.theme = effective;

    if (themeBtn) {
      var labels = THEME_LABELS[lang] || THEME_LABELS.en;
      var label = labels[themeMode] || labels.auto;
      themeBtn.textContent = label;
    }
  }

  function initSystemThemeListener() {
    if (!window.matchMedia) {
      return;
    }
    try {
      if (!colorSchemeMql) {
        colorSchemeMql = window.matchMedia('(prefers-color-scheme: dark)');
      }
      if (!colorSchemeMql) {
        return;
      }
      var handler = function () {
        // Only react automatically when the user selected "auto"
        if ((root.dataset.themeMode || 'auto') === 'auto') {
          applyTheme('auto');
        }
      };
      if (typeof colorSchemeMql.addEventListener === 'function') {
        colorSchemeMql.addEventListener('change', handler);
      } else if (typeof colorSchemeMql.addListener === 'function') {
        // Safari 12 and older implementations
        colorSchemeMql.addListener(handler);
      }
    } catch (e) {}
  }

  var storedTheme = null;
  try {
    storedTheme = window.localStorage.getItem(THEME_KEY);
  } catch (e) {}

  initSystemThemeListener();
  applyTheme(storedTheme || 'auto');

  if (themeBtn) {
    themeBtn.addEventListener('click', function () {
      var currentMode = root.dataset.themeMode || 'auto';
      var next = currentMode === 'light' ? 'dark' : currentMode === 'dark' ? 'auto' : 'light';
      try {
        window.localStorage.setItem(THEME_KEY, next);
      } catch (e) {}
      applyTheme(next);
    });
  }

  if (navBtn) {
    navBtn.addEventListener('click', function () {
      toggleNav();
    });
  }

  if (navOverlay) {
    navOverlay.addEventListener('click', function () {
      closeNav();
    });
  }

  if (sidebar) {
    sidebar.addEventListener('click', function (e) {
      if (e.target && e.target.tagName === 'A' && document.body.classList.contains('bm-nav-open')) {
        closeNav();
      }
    });
  }

  // Close nav when resizing to desktop
  if (typeof window.matchMedia === 'function') {
    var desktopMql = window.matchMedia('(min-width: 961px)');
    var desktopHandler = function (e) {
      if (e.matches) {
        closeNav();
      }
    };
    if (desktopMql.addEventListener) {
      desktopMql.addEventListener('change', desktopHandler);
    } else if (desktopMql.addListener) {
      desktopMql.addListener(desktopHandler);
    }
  }

  // With mkdocs-static-i18n docs_structure: suffix, localized pages are
  // served under a locale prefix (e.g. /zh/..., /fr/...).
  function getCurrentLangFromPath() {
    var path = window.location.pathname || '/';
    // trim leading/trailing slashes
    path = path.replace(/^\/+|\/+$/g, '');
    if (!path) {
      return 'en';
    }
    var segments = path.split('/');
    var first = segments[0];
    if (first === 'zh') {
      return 'zh';
    }
    return 'en';
  }

  function buildPathForLang(targetLang) {
    var path = window.location.pathname || '/';
    // Remove leading and trailing slashes for processing
    path = path.replace(/^\/+|\/+$/g, '');

    var segments = path ? path.split('/').filter(function(s) { return s; }) : [];
    var knownLocales = ['zh'];

    // Strip existing locale prefix from current path, if any
    if (segments.length > 0 && knownLocales.indexOf(segments[0]) !== -1) {
      segments.shift();
    }

    // Check if the last segment is a file (has an extension)
    // Files like search.html should not have trailing slashes
    var lastSegment = segments.length > 0 ? segments[segments.length - 1] : '';
    var isFile = lastSegment && lastSegment.indexOf('.') !== -1 && 
                 lastSegment !== '.' && lastSegment !== '..' &&
                 lastSegment.split('.').length > 1;
    
    var rel = segments.join('/');
    var trailingSlash = (rel && !isFile) ? '/' : '';

    if (targetLang === 'en') {
      // Default language has no locale prefix
      return '/' + (rel ? rel + trailingSlash : '');
    }

    // Non-default language: prefix locale
    return '/' + targetLang + '/' + (rel ? rel + trailingSlash : '');
  }

  var currentLang = getCurrentLangFromPath();
  var storedLang = null;
  try {
    storedLang = window.localStorage.getItem(LANG_KEY);
  } catch (e) {}

  // If the user has explicitly chosen a language before, always honor that
  // and redirect into the stored locale on load.
  if (storedLang && storedLang !== currentLang) {
    window.location.pathname = buildPathForLang(storedLang);
    return;
  }

  if (langSelect) {
    langSelect.value = storedLang || currentLang;
    langSelect.addEventListener('change', function () {
      var target = this.value || 'en';
      try {
        window.localStorage.setItem(LANG_KEY, target);
      } catch (e) {}
      window.location.pathname = buildPathForLang(target);
    });
  }

  // Automatic locale choice: only when the user has NOT manually chosen a language
  // (i.e. there is no storedLang yet). In that case, prefer zh for zh-* browsers.
  if (!storedLang) {
    var navLang = (navigator.language || navigator.userLanguage || 'en').toLowerCase();
    if (navLang.indexOf('zh') === 0 && currentLang !== 'zh') {
      window.location.pathname = buildPathForLang('zh');
    }
  }
})();
