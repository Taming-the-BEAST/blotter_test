(function() {
  'use strict';

  // Filters now support multiple selections (arrays)
  const filters = {
    level: [],      // empty = all
    type: [],
    package: [],
    domain: [],
    search: '',
    showLegacy: false
  };

  let currentSort = 'date';
  let searchMode = 'keyword';
  let pagefindInstance = null;

  // Initialize
  document.addEventListener('DOMContentLoaded', function() {
    loadFiltersFromURL();
    setupFilterButtons();
    setupSortButtons();
    setupSearch();
    setupSearchModeToggle();
    setupKeywordChips();
    setupLegacyToggle();
    initPagefind();
    applyFilters();
  });

  function setupFilterButtons() {
    document.querySelectorAll('[data-filter]').forEach(btn => {
      btn.addEventListener('click', function() {
        const filterType = this.dataset.filter;
        const value = this.dataset.value;

        if (value === 'all') {
          // Clear all selections for this filter
          filters[filterType] = [];
          document.querySelectorAll(`[data-filter="${filterType}"]`)
            .forEach(b => b.classList.remove('active'));
          this.classList.add('active');
        } else {
          // Toggle this value
          const index = filters[filterType].indexOf(value);
          if (index > -1) {
            // Remove from selection
            filters[filterType].splice(index, 1);
            this.classList.remove('active');
          } else {
            // Add to selection
            filters[filterType].push(value);
            this.classList.add('active');
          }

          // Update "All" button state
          const allBtn = document.querySelector(`[data-filter="${filterType}"][data-value="all"]`);
          if (allBtn) {
            if (filters[filterType].length === 0) {
              allBtn.classList.add('active');
            } else {
              allBtn.classList.remove('active');
            }
          }
        }

        applyFilters();
      });
    });
  }

  function setupSortButtons() {
    document.querySelectorAll('[data-sort]').forEach(btn => {
      btn.addEventListener('click', function() {
        const sortType = this.dataset.sort;

        document.querySelectorAll('[data-sort]')
          .forEach(b => b.classList.remove('active'));
        this.classList.add('active');

        currentSort = sortType;
        sortCards();
      });
    });
  }

  function sortCards() {
    const grid = document.getElementById('tutorial-grid');
    if (!grid) return;

    const cards = Array.from(grid.querySelectorAll('.tutorial-card'));
    const levelOrder = { 'Beginner': 1, 'Intermediate': 2, 'Professional': 3 };

    cards.sort((a, b) => {
      switch (currentSort) {
        case 'date':
          const dateA = a.dataset.date || '0';
          const dateB = b.dataset.date || '0';
          return dateB.localeCompare(dateA);

        case 'title':
          const titleA = a.dataset.title || '';
          const titleB = b.dataset.title || '';
          return titleA.localeCompare(titleB);

        case 'level':
          const levelA = levelOrder[a.dataset.level] || 99;
          const levelB = levelOrder[b.dataset.level] || 99;
          return levelA - levelB;

        default:
          return 0;
      }
    });

    cards.forEach(card => grid.appendChild(card));
  }

  function setupSearch() {
    const searchInput = document.getElementById('tutorial-search');
    if (searchInput) {
      searchInput.addEventListener('input', function() {
        filters.search = this.value.toLowerCase();
        applyFilters();
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

  function setupSearchModeToggle() {
    const modeRadios = document.querySelectorAll('input[name="search-mode"]');
    const keywordContainer = document.getElementById('keyword-search-container');
    const fulltextContainer = document.getElementById('fulltext-search-container');

    modeRadios.forEach(radio => {
      radio.addEventListener('change', function() {
        searchMode = this.value;

        if (searchMode === 'keyword') {
          keywordContainer.style.display = 'block';
          fulltextContainer.style.display = 'none';
          // Show all cards, apply keyword filter
          applyFilters();
        } else {
          keywordContainer.style.display = 'none';
          fulltextContainer.style.display = 'block';
          // Clear keyword search and show all cards
          filters.search = '';
          const searchInput = document.getElementById('tutorial-search');
          if (searchInput) searchInput.value = '';
          applyFilters();
        }
      });
    });
  }

  function setupKeywordChips() {
    document.querySelectorAll('.keyword-chip').forEach(chip => {
      chip.addEventListener('click', function() {
        const keyword = this.dataset.keyword;
        const searchInput = document.getElementById('tutorial-search');

        if (searchInput) {
          searchInput.value = keyword;
          filters.search = keyword.toLowerCase();
          applyFilters();
        }
      });
    });
  }

  function initPagefind() {
    const pagefindContainer = document.getElementById('pagefind-search');
    if (pagefindContainer && typeof PagefindUI !== 'undefined') {
      pagefindInstance = new PagefindUI({
        element: '#pagefind-search',
        showSubResults: true,
        showImages: false,
        excerptLength: 15
      });
    }
  }

  function applyFilters() {
    const cards = document.querySelectorAll('.tutorial-card');
    let visibleCount = 0;

    cards.forEach(card => {
      let show = true;

      // Level filter (OR logic - match any selected)
      if (filters.level.length > 0) {
        if (!filters.level.includes(card.dataset.level)) {
          show = false;
        }
      }

      // Type filter
      if (filters.type.length > 0) {
        if (!filters.type.includes(card.dataset.type)) {
          show = false;
        }
      }

      // Package filter (OR logic - card matches if it has ANY of the selected packages)
      if (filters.package.length > 0) {
        const cardPackages = (card.dataset.packages || '').split(',').filter(p => p);
        const hasMatch = filters.package.some(pkg => cardPackages.includes(pkg));
        if (!hasMatch) {
          show = false;
        }
      }

      // Domain filter (OR logic)
      if (filters.domain.length > 0) {
        const cardDomains = (card.dataset.domains || '').split(',').filter(d => d);
        const hasMatch = filters.domain.some(dom => cardDomains.includes(dom));
        if (!hasMatch) {
          show = false;
        }
      }

      // Search filter
      if (filters.search) {
        const searchText = (card.dataset.search || '').toLowerCase();
        if (!searchText.includes(filters.search)) {
          show = false;
        }
      }

      // Legacy filter
      if (!filters.showLegacy && card.dataset.status === 'legacy') {
        show = false;
      }

      card.style.display = show ? 'block' : 'none';
      if (show) visibleCount++;
    });

    // Update count
    const countEl = document.getElementById('tutorial-count');
    if (countEl) {
      countEl.textContent = visibleCount;
    }

    updateURL();
  }

  function updateURL() {
    const params = new URLSearchParams();

    if (filters.level.length > 0) params.set('level', filters.level.join(','));
    if (filters.type.length > 0) params.set('type', filters.type.join(','));
    if (filters.package.length > 0) params.set('package', filters.package.join(','));
    if (filters.domain.length > 0) params.set('domain', filters.domain.join(','));
    if (filters.search) params.set('search', filters.search);
    if (filters.showLegacy) params.set('legacy', '1');
    if (currentSort !== 'date') params.set('sort', currentSort);

    const newURL = window.location.pathname +
      (params.toString() ? '?' + params.toString() : '');

    window.history.replaceState({}, '', newURL);
  }

  function loadFiltersFromURL() {
    const params = new URLSearchParams(window.location.search);

    // Parse comma-separated values into arrays
    if (params.has('level')) {
      filters.level = params.get('level').split(',');
    }
    if (params.has('type')) {
      filters.type = params.get('type').split(',');
    }
    if (params.has('package')) {
      filters.package = params.get('package').split(',');
    }
    if (params.has('domain')) {
      filters.domain = params.get('domain').split(',');
    }
    if (params.has('search')) {
      filters.search = params.get('search');
      setTimeout(function() {
        const searchInput = document.getElementById('tutorial-search');
        if (searchInput) {
          searchInput.value = filters.search;
        }
      }, 100);
    }
    if (params.has('legacy')) {
      filters.showLegacy = true;
      const legacyToggle = document.getElementById('show-legacy');
      if (legacyToggle) {
        legacyToggle.checked = true;
      }
    }
    if (params.has('sort')) {
      currentSort = params.get('sort');
      const sortBtn = document.querySelector(`[data-sort="${currentSort}"]`);
      if (sortBtn) {
        document.querySelectorAll('[data-sort]').forEach(b => b.classList.remove('active'));
        sortBtn.classList.add('active');
      }
    }

    // Activate filter buttons from URL
    ['level', 'type', 'package', 'domain'].forEach(filterType => {
      if (filters[filterType].length > 0) {
        // Deactivate "All" button
        const allBtn = document.querySelector(`[data-filter="${filterType}"][data-value="all"]`);
        if (allBtn) allBtn.classList.remove('active');

        // Activate selected buttons
        filters[filterType].forEach(value => {
          const btn = document.querySelector(`[data-filter="${filterType}"][data-value="${value}"]`);
          if (btn) btn.classList.add('active');
        });
      }
    });

    setTimeout(sortCards, 100);
  }
})();
