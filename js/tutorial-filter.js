(function() {
  'use strict';

  const filters = {
    level: 'all',
    type: 'all',
    package: 'all',
    search: '',
    showLegacy: false
  };

  let pagefindUI;
  let searchResults = new Set(); // Store URLs from Pagefind results

  // Initialize
  document.addEventListener('DOMContentLoaded', function() {
    loadFiltersFromURL();
    setupFilterButtons();
    setupPagefind();
    setupLegacyToggle();
    applyFilters();
  });

  function setupFilterButtons() {
    document.querySelectorAll('.filter-btn').forEach(btn => {
      btn.addEventListener('click', function() {
        const filterType = this.dataset.filter;
        const value = this.dataset.value;

        // Update active state
        document.querySelectorAll(`[data-filter="${filterType}"]`)
          .forEach(b => b.classList.remove('active'));
        this.classList.add('active');

        // Update filter
        filters[filterType] = value;
        applyFilters();
      });
    });
  }

  function setupPagefind() {
    // Initialize Pagefind UI
    if (typeof PagefindUI === 'undefined') {
      console.warn('Pagefind UI not loaded. Search will not be available.');
      return;
    }

    pagefindUI = new PagefindUI({
      element: "#pagefind-search",
      showSubResults: true,
      showImages: false,
      excerptLength: 15,
      processResult: function(result) {
        // Store the result URL for filtering
        if (result.url) {
          searchResults.add(result.url);
        }
        return result;
      }
    });

    // Listen for search events
    const searchContainer = document.getElementById('pagefind-search');
    if (searchContainer) {
      // Watch for input changes in Pagefind's search box
      const observer = new MutationObserver(function() {
        const pagefindInput = searchContainer.querySelector('input[type="text"]');
        if (pagefindInput && !pagefindInput.dataset.listenerAdded) {
          pagefindInput.dataset.listenerAdded = 'true';
          pagefindInput.addEventListener('input', function() {
            filters.search = this.value.toLowerCase();
            // Clear search results if empty
            if (!filters.search) {
              searchResults.clear();
            }
            // Apply filters after a short delay to let Pagefind process
            setTimeout(applyFilters, 300);
          });
        }
      });

      observer.observe(searchContainer, {
        childList: true,
        subtree: true
      });
    }
  }

  function setupLegacyToggle() {
    const toggle = document.getElementById('show-legacy');
    if (toggle) {
      toggle.addEventListener('change', function() {
        filters.showLegacy = this.checked;
        applyFilters();
      });
    }
  }

  function applyFilters() {
    const cards = document.querySelectorAll('.tutorial-card');
    let visibleCount = 0;

    cards.forEach(card => {
      let show = true;

      // Level filter
      if (filters.level !== 'all' && card.dataset.level !== filters.level) {
        show = false;
      }

      // Type filter
      if (filters.type !== 'all' && card.dataset.type !== filters.type) {
        show = false;
      }

      // Package filter
      if (filters.package !== 'all') {
        const packages = (card.dataset.packages || '').split(',');
        if (!packages.includes(filters.package)) {
          show = false;
        }
      }

      // Search filter (fallback to simple search if Pagefind hasn't loaded results yet)
      if (filters.search) {
        // Try to get the card's tutorial URL
        const cardLink = card.querySelector('h3 a');
        const cardUrl = cardLink ? cardLink.getAttribute('href') : null;

        // If Pagefind has results, use them; otherwise fallback to simple search
        if (searchResults.size > 0) {
          // Check if this card's URL is in Pagefind results
          let foundInResults = false;
          if (cardUrl) {
            searchResults.forEach(resultUrl => {
              if (resultUrl.includes(cardUrl) || cardUrl.includes(resultUrl)) {
                foundInResults = true;
              }
            });
          }
          if (!foundInResults) {
            show = false;
          }
        } else {
          // Fallback to simple keyword search
          const searchText = (
            card.dataset.search + ' ' +
            card.dataset.keywords
          ).toLowerCase();

          if (!searchText.includes(filters.search)) {
            show = false;
          }
        }
      }

      // Legacy filter
      if (!filters.showLegacy && card.dataset.status === 'legacy') {
        show = false;
      }

      // Apply visibility
      card.style.display = show ? 'block' : 'none';
      if (show) visibleCount++;
    });

    // Update count
    const countEl = document.getElementById('tutorial-count');
    if (countEl) {
      countEl.textContent = visibleCount;
    }

    // Update URL for sharing
    updateURL();
  }

  function updateURL() {
    const params = new URLSearchParams();

    if (filters.level !== 'all') params.set('level', filters.level);
    if (filters.type !== 'all') params.set('type', filters.type);
    if (filters.package !== 'all') params.set('package', filters.package);
    if (filters.search) params.set('search', filters.search);
    if (filters.showLegacy) params.set('legacy', '1');

    const newURL = window.location.pathname +
      (params.toString() ? '?' + params.toString() : '');

    window.history.replaceState({}, '', newURL);
  }

  // Load filters from URL on page load
  function loadFiltersFromURL() {
    const params = new URLSearchParams(window.location.search);

    if (params.has('level')) filters.level = params.get('level');
    if (params.has('type')) filters.type = params.get('type');
    if (params.has('package')) filters.package = params.get('package');
    if (params.has('search')) {
      filters.search = params.get('search');
      // Pagefind will populate its own search box, so we'll set it after initialization
      setTimeout(function() {
        const pagefindInput = document.querySelector('#pagefind-search input[type="text"]');
        if (pagefindInput) {
          pagefindInput.value = filters.search;
          // Trigger search
          pagefindInput.dispatchEvent(new Event('input', { bubbles: true }));
        }
      }, 500);
    }
    if (params.has('legacy')) {
      filters.showLegacy = true;
      const legacyToggle = document.getElementById('show-legacy');
      if (legacyToggle) {
        legacyToggle.checked = true;
      }
    }

    // Activate corresponding buttons
    if (filters.level !== 'all') {
      const levelBtn = document.querySelector(`[data-filter="level"][data-value="${filters.level}"]`);
      if (levelBtn) {
        document.querySelectorAll('[data-filter="level"]').forEach(b => b.classList.remove('active'));
        levelBtn.classList.add('active');
      }
    }
    if (filters.type !== 'all') {
      const typeBtn = document.querySelector(`[data-filter="type"][data-value="${filters.type}"]`);
      if (typeBtn) {
        document.querySelectorAll('[data-filter="type"]').forEach(b => b.classList.remove('active'));
        typeBtn.classList.add('active');
      }
    }
    if (filters.package !== 'all') {
      const packageBtn = document.querySelector(`[data-filter="package"][data-value="${filters.package}"]`);
      if (packageBtn) {
        document.querySelectorAll('[data-filter="package"]').forEach(b => b.classList.remove('active'));
        packageBtn.classList.add('active');
      }
    }
  }
})();
