(function () {
  'use strict';

  const API_BASE_URL =
    (window.FNF_CONFIG && window.FNF_CONFIG.API_BASE_URL) || '';

  // Online requests are blocked until config.js explicitly confirms
  // that this menu is connected to the correct backend.
  const API_BASE_URL_VERIFIED =
    !!(window.FNF_CONFIG && window.FNF_CONFIG.VERIFIED === true);

  const ASSET_HOST = API_BASE_URL.endsWith('/api')
    ? API_BASE_URL.slice(0, -4)
    : API_BASE_URL;

  const els = {
    loadingState: document.getElementById('loadingState'),
    loadingSlowHint: document.getElementById('loadingSlowHint'),
    errorState: document.getElementById('errorState'),
    errorTitle: document.getElementById('errorTitle'),
    errorMessage: document.getElementById('errorMessage'),
    retryBtn: document.getElementById('retryBtn'),

    successState: document.getElementById('successState'),
    successHeading: document.getElementById('successHeading'),
    successSubtext: document.getElementById('successSubtext'),
    successTable: document.getElementById('successTable'),
    successOrderNumber: document.getElementById('successOrderNumber'),
    successTotal: document.getElementById('successTotal'),
    successItems: document.getElementById('successItems'),
    successStatus: document.getElementById('successStatus'),
    successStatusText: document.getElementById('successStatusText'),
    doneBtn: document.getElementById('doneBtn'),

    feedbackBox: document.getElementById('feedbackBox'),
    feedbackStars: document.getElementById('feedbackStars'),
    feedbackComment: document.getElementById('feedbackComment'),
    submitFeedbackBtn: document.getElementById('submitFeedbackBtn'),
    feedbackMessage: document.getElementById('feedbackMessage'),

    app: document.getElementById('app'),
    tableBadge: document.getElementById('tableBadge'),

    searchInput: document.getElementById('searchInput'),
    clearSearch: document.getElementById('clearSearch'),

    categoryChips: document.getElementById('categoryChips'),
    productList: document.getElementById('productList'),

    searchEmpty: document.getElementById('searchEmpty'),
    clearSearchBtn: document.getElementById('clearSearchBtn'),

    cartBar: document.getElementById('cartBar'),
    cartCount: document.getElementById('cartCount'),
    cartBarTotal: document.getElementById('cartBarTotal'),

    cartOverlay: document.getElementById('cartOverlay'),
    closeCart: document.getElementById('closeCart'),

    cartLines: document.getElementById('cartLines'),
    cartItemCount: document.getElementById('cartItemCount'),
    cartTotal: document.getElementById('cartTotal'),

    customerName: document.getElementById('customerName'),
    customerPhone: document.getElementById('customerPhone'),
    orderNote: document.getElementById('orderNote'),

    onlinePaymentOption: document.getElementById('onlinePaymentOption'),
    payUpiBtn: document.getElementById('payUpiBtn'),
    upiHelpText: document.getElementById('upiHelpText'),

    upiPendingState: document.getElementById('upiPendingState'),
    upiPendingHeading: document.getElementById('upiPendingHeading'),
    upiPendingSubtext: document.getElementById('upiPendingSubtext'),
    upiPendingTable: document.getElementById('upiPendingTable'),
    upiPendingOrderNumber: document.getElementById('upiPendingOrderNumber'),
    upiPendingTotal: document.getElementById('upiPendingTotal'),
    upiReopenBtn: document.getElementById('upiReopenBtn'),
    upiPendingError: document.getElementById('upiPendingError'),
    upiCancelBtn: document.getElementById('upiCancelBtn'),
    upiPendingStatusCard: document.getElementById('upiPendingStatusCard'),
    upiPendingStatusText: document.getElementById('upiPendingStatusText'),

    checkoutError: document.getElementById('checkoutError'),
    placeOrderBtn: document.getElementById('placeOrderBtn'),

  };

  const state = {
    paymentOptions: {
      onlineUpi: false,
      upiId: '',
      cafeName: 'FAST N FRESH CAFE',
    },

    tableNumber: null,
    tableName: null,

    categories: [],
    items: [],

    activeCategory: 'all',
    searchQuery: '',

    cart: new Map(),

    loading: false,

    // Reused when retrying the same cart/order request.
    clientRequestId: null,

    tracking: {
      orderId: null,
      token: null,
      timer: null,
      status: null,
    },

    feedbackRating: 0,

    // Created when the customer starts a UPI intent. The order remains
    // payment_initiated until staff verifies the money at checkout.
    upiOrder: null,
  };

  function generateRequestId() {
    if (
      window.crypto &&
      typeof window.crypto.randomUUID === 'function'
    ) {
      return window.crypto.randomUUID();
    }

    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(
      /[xy]/g,
      (c) => {
        const r = (Math.random() * 16) | 0;
        const v =
          c === 'x'
            ? r
            : (r & 0x3) | 0x8;

        return v.toString(16);
      }
    );
  }

  function invalidateClientRequestId() {
    state.clientRequestId = null;
  }

  /* =========================================================
     HELPERS
     ========================================================= */

  function formatMoney(value) {
    return (
      '₹' +
      Number(value || 0).toLocaleString('en-IN', {
        maximumFractionDigits: 2,
      })
    );
  }

  let slowHintTimer = null;

  function startSlowHintTimer() {
    clearSlowHintTimer();

    if (!els.loadingSlowHint) return;

    slowHintTimer = window.setTimeout(() => {
      els.loadingSlowHint.classList.remove('hidden');
    }, 6000);
  }

  function clearSlowHintTimer() {
    if (slowHintTimer) {
      window.clearTimeout(slowHintTimer);
      slowHintTimer = null;
    }

    if (els.loadingSlowHint) {
      els.loadingSlowHint.classList.add('hidden');
    }
  }

  function showState(name) {
    if (name !== 'loadingState') {
      clearSlowHintTimer();
    }

    [
      'loadingState',
      'errorState',
      'successState',
      'upiPendingState',
      'app',
    ].forEach((key) => {
      if (!els[key]) return;

      els[key].classList.toggle(
        'hidden',
        key !== name
      );
    });
  }

  function showFatalError(title, message) {
    if (els.errorTitle) {
      els.errorTitle.textContent = title;
    }

    if (els.errorMessage) {
      els.errorMessage.textContent = message;
    }

    showState('errorState');
  }

  async function apiRequest(path, options = {}, attempt = 0) {
    if (
      !API_BASE_URL ||
      API_BASE_URL.includes(
        'your-deployed-api-domain.com'
      )
    ) {
      throw new Error(
        'Cafe menu is not configured correctly.'
      );
    }

    if (!API_BASE_URL_VERIFIED) {
      throw new Error(
        'This menu has not been confirmed to be connected to the right server yet. Please ask staff, or see the instructions in config.js.'
      );
    }

    let response;

    const controller = new AbortController();

    const timeoutId = window.setTimeout(
      () => controller.abort(),
      45000
    );

    try {
      response = await fetch(
        API_BASE_URL + path,
        {
          headers: {
            'Content-Type': 'application/json',
          },
          ...options,
          signal: controller.signal,
        }
      );
    } catch (error) {
      // Render can briefly cold-start. Retry GET requests once before showing
      // the customer an error. Never retry POST requests automatically.
      const method = String(options.method || 'GET').toUpperCase();
      if (method === 'GET' && attempt === 0) {
        await new Promise((resolve) => window.setTimeout(resolve, 1200));
        return apiRequest(path, options, 1);
      }

      if (error?.name === 'AbortError') {
        throw new Error(
          'Cafe server is waking up. Please wait a moment and try again.'
        );
      }

      throw new Error(
        'Network error. Please check your internet connection.'
      );
    } finally {
      window.clearTimeout(timeoutId);
    }

    let body;

    try {
      body = await response.json();
    } catch (_) {
      throw new Error(
        'Cafe server returned an invalid response.'
      );
    }

    if (!response.ok || !body.success) {
      throw new Error(
        body?.message ||
          'Something went wrong. Please try again.'
      );
    }

    return body;
  }

  function getTableNumberFromUrl() {
    const params = new URLSearchParams(
      window.location.search
    );

    const raw = params.get('table');
    const number = Number(raw);

    if (
      !raw ||
      !Number.isInteger(number) ||
      number < 1
    ) {
      return null;
    }

    return number;
  }

  /* =========================================================
     RETURNING CUSTOMER
     ========================================================= */

  const PENDING_ORDER_KEY = 'fnf_last_order';
  const PENDING_UPI_ORDER_KEY = 'fnf_pending_upi_order';
  const UPI_SESSION_KEY = 'fnf_upi_session_active';

  function hasActiveUpiSession() {
    try {
      return sessionStorage.getItem(UPI_SESSION_KEY) === '1';
    } catch (_) {
      return false;
    }
  }

  function setActiveUpiSession(active) {
    try {
      if (active) {
        sessionStorage.setItem(UPI_SESSION_KEY, '1');
      } else {
        sessionStorage.removeItem(UPI_SESSION_KEY);
      }
    } catch (_) {}
  }

  function clearPendingOrder() {
    try {
      localStorage.removeItem(PENDING_ORDER_KEY);
    } catch (_) {}
  }

  function readPendingOrder() {
    try {
      const raw =
        localStorage.getItem(PENDING_ORDER_KEY);

      if (!raw) return null;

      const parsed = JSON.parse(raw);

      if (
        !parsed ||
        !parsed.orderId ||
        !parsed.token
      ) {
        return null;
      }

      return parsed;
    } catch (_) {
      return null;
    }
  }

  function renderOrderItems(items) {
    if (!els.successItems) return;

    els.successItems.innerHTML = '';

    (items || []).forEach((item) => {
      const row =
        document.createElement('div');

      row.className =
        'success-item-row';

      const nameWrap =
        document.createElement('span');

      nameWrap.className =
        'success-item-name';

      const qty =
        document.createElement('span');

      qty.className =
        'success-item-qty';

      qty.textContent =
        `${item.quantity}× `;

      nameWrap.appendChild(qty);

      nameWrap.appendChild(
        document.createTextNode(
          item.name || ''
        )
      );

      const price =
        document.createElement('span');

      price.className =
        'success-item-price';

      const lineTotal =
        item.total != null
          ? item.total
          : (item.price || 0) *
            (item.quantity || 1);

      price.textContent =
        formatMoney(lineTotal);

      row.appendChild(nameWrap);
      row.appendChild(price);

      els.successItems.appendChild(row);
    });
  }

  async function tryRestorePendingOrder() {
    const pending =
      readPendingOrder();

    if (!pending) return false;

    try {
      const response =
        await apiRequest(
          `/public/orders/${encodeURIComponent(
            pending.orderId
          )}/status?token=${encodeURIComponent(
            pending.token
          )}`
        );

      const data =
        response.data || {};

      if (data.status === 'voided') {
        clearPendingOrder();
        return false;
      }

      if (els.successHeading) {
        els.successHeading.textContent =
          'Welcome back!';
      }

      if (els.successSubtext) {
        els.successSubtext.textContent =
          "Here's your order from this table.";
      }

      if (els.successTable) {
        els.successTable.textContent =
          data.tableName ||
          `Table ${data.tableNumber}`;
      }

      if (els.successOrderNumber) {
        els.successOrderNumber.textContent =
          `#${data.orderNumber}`;
      }

      if (els.successTotal) {
        els.successTotal.textContent =
          formatMoney(data.total);
      }

      renderOrderItems(data.items);

      state.feedbackRating = 0;

      if (els.feedbackBox) {
        els.feedbackBox.classList.add('hidden');
      }

      if (els.feedbackMessage) {
        els.feedbackMessage.textContent = '';
      }

      startOrderTracking(
        pending.orderId,
        pending.token,
        data.status
      );

      showState('successState');

      return true;
    } catch (_) {
      clearPendingOrder();
      return false;
    }
  }

  /* =========================================================
     INITIAL LOAD
     ========================================================= */

  async function init() {
    showState('loadingState');

    const tableNumber =
      getTableNumberFromUrl();

    if (!tableNumber) {
      showFatalError(
        'Table not found',
        'Please scan the QR code placed on your table.'
      );
      return;
    }

    startSlowHintTimer();

    try {
      const tableResponse =
        await apiRequest(
          `/public/tables/${tableNumber}`
        );

      state.tableNumber =
        tableResponse.data.tableNumber;

      state.tableName =
        tableResponse.data.tableName;

      // The menu is the primary customer experience. Payment configuration
      // must never prevent the catalog from rendering.
      const menuResponse = await apiRequest('/public/menu');

      state.categories =
        menuResponse.categories || [];

      state.items =
        menuResponse.items || [];

      try {
        const paymentResponse = await apiRequest('/public/payment-options');
        state.paymentOptions =
          paymentResponse.data || state.paymentOptions;
      } catch (_) {
        // Keep the menu usable when payment settings are unavailable.
        state.paymentOptions = {
          ...state.paymentOptions,
          onlineUpi: false,
          upiId: '',
        };
      }

      /*
       * IMPORTANT:
       *
       * The backend is the authority for whether online payment
       * is actually available.
       *
       * Do NOT infer online payment availability from the presence
       * of a UPI ID.
       *
       * This keeps the customer payment flow aligned with server verification
       * simply because an operator has entered a UPI ID.
       */
      const onlineUpiEnabled =
        state.paymentOptions.onlineUpi === true;

      state.paymentOptions.onlineUpi =
        onlineUpiEnabled;

      state.paymentOptions.upiId =
        String(
          state.paymentOptions.upiId || ''
        ).trim();

      if (els.onlinePaymentOption) {
        els.onlinePaymentOption.style.display =
          onlineUpiEnabled
            ? 'flex'
            : 'none';
      }

      if (els.upiHelpText) {
        els.upiHelpText.style.display =
          onlineUpiEnabled
            ? 'block'
            : 'none';

        if (onlineUpiEnabled) {
          els.upiHelpText.textContent =
            'Pay in your UPI app. The cafe will verify the payment before marking the order as paid.';
        }
      }

      updatePaymentActions();

      renderApp();

      showState('app');

      const restoredUpi =
        await tryRestorePendingUpiOrder();

      if (restoredUpi) return;

      const restored =
        await tryRestorePendingOrder();

      if (restored) return;
    } catch (error) {
      showFatalError(
        'Unable to load menu',
        error.message ||
          'Please try again or ask a staff member for help.'
      );
    }
  }

  /* =========================================================
     MAIN APP
     ========================================================= */

  function renderApp() {
    renderTable();
    renderCategories();
    renderProducts();
    updateCartBar();
  }

  function renderTable() {
    const tableNumber =
      state.tableName
        ? state.tableName.replace(
            /^Table\s*/i,
            ''
          )
        : state.tableNumber;

    if (els.tableBadge) {
      els.tableBadge.textContent =
        `Table ${tableNumber}`;
    }
  }

  /* =========================================================
     CATEGORIES
     ========================================================= */

  function renderCategories() {
    if (!els.categoryChips) return;

    els.categoryChips.innerHTML = '';

    els.categoryChips.appendChild(
      createCategoryButton(
        'All',
        'all'
      )
    );

    state.categories.forEach(
      (category) => {
        els.categoryChips.appendChild(
          createCategoryButton(
            category.name,
            category._id
          )
        );
      }
    );
  }

  function createCategoryButton(
    label,
    value
  ) {
    const button =
      document.createElement('button');

    button.type = 'button';

    button.className =
      'chip' +
      (
        state.activeCategory === value
          ? ' active'
          : ''
      );

    button.textContent = label;

    button.addEventListener(
      'click',
      () => {
        state.activeCategory = value;

        renderCategories();
        renderProducts();
      }
    );

    return button;
  }

  /* =========================================================
     SEARCH
     ========================================================= */

  function getFilteredItems() {
    const query =
      state.searchQuery
        .trim()
        .toLowerCase();

    return state.items.filter(
      (item) => {
        const categoryMatch =
          state.activeCategory === 'all' ||
          item.category ===
            state.activeCategory;

        if (!categoryMatch) {
          return false;
        }

        if (!query) {
          return true;
        }

        const name =
          String(item.name || '')
            .toLowerCase();

        const category =
          String(
            item.categoryName || ''
          ).toLowerCase();

        return (
          name.includes(query) ||
          category.includes(query)
        );
      }
    );
  }

  function updateSearchUI() {
    if (!els.clearSearch) return;

    const hasSearch =
      state.searchQuery
        .trim()
        .length > 0;

    els.clearSearch.classList.toggle(
      'hidden',
      !hasSearch
    );
  }

  /* =========================================================
     PRODUCTS
     ========================================================= */

  function renderProducts() {
    if (!els.productList) return;

    els.productList.innerHTML = '';

    const filteredItems =
      getFilteredItems();

    if (filteredItems.length === 0) {
      els.productList.classList.add(
        'hidden'
      );

      if (els.searchEmpty) {
        els.searchEmpty.classList.remove(
          'hidden'
        );
      }

      return;
    }

    els.productList.classList.remove(
      'hidden'
    );

    if (els.searchEmpty) {
      els.searchEmpty.classList.add(
        'hidden'
      );
    }

    const grouped =
      new Map();

    filteredItems.forEach(
      (item) => {
        const categoryName =
          item.categoryName ||
          'Other';

        if (!grouped.has(categoryName)) {
          grouped.set(
            categoryName,
            []
          );
        }

        grouped
          .get(categoryName)
          .push(item);
      }
    );

    grouped.forEach(
      (
        products,
        categoryName
      ) => {
        const heading =
          document.createElement('div');

        heading.className =
          'category-heading';

        heading.textContent =
          categoryName;

        els.productList.appendChild(
          heading
        );

        products.forEach(
          (product) => {
            els.productList.appendChild(
              renderProductCard(product)
            );
          }
        );
      }
    );
  }

  function renderProductCard(item) {
    const card =
      document.createElement('div');

    card.className =
      'product-card';

    if (item.image) {
      const image =
        document.createElement('img');

      image.className =
        'product-image';

      image.loading = 'lazy';

      image.alt =
        item.name || 'Food';

      image.src =
        item.image.startsWith('http')
          ? item.image
          : ASSET_HOST + item.image;

      image.onerror = () => {
        image.style.display =
          'none';
      };

      card.appendChild(image);
    } else {
      const placeholder =
        document.createElement('div');

      placeholder.className =
        'product-image placeholder';

      placeholder.textContent =
        String(item.name || 'Food')
          .slice(0, 2)
          .toUpperCase();

      card.appendChild(
        placeholder
      );
    }

    const info =
      document.createElement('div');

    info.className =
      'product-info';

    const name =
      document.createElement('div');

    name.className =
      'product-name';

    name.textContent =
      item.name;

    info.appendChild(name);

    if (item.available) {
      const price =
        document.createElement('div');

      price.className =
        'product-price';

      price.textContent =
        formatMoney(item.price);

      info.appendChild(price);
    } else {
      const unavailable =
        document.createElement('div');

      unavailable.className =
        'product-unavailable';

      unavailable.textContent =
        'Currently unavailable';

      info.appendChild(
        unavailable
      );
    }

    card.appendChild(info);

    const action =
      document.createElement('div');

    action.className =
      'product-action';

    action.appendChild(
      renderQuantityControl(item)
    );

    card.appendChild(action);

    return card;
  }

  /* =========================================================
     QUANTITY
     ========================================================= */

  function renderQuantityControl(item) {
    const wrapper =
      document.createElement('div');

    const existing =
      state.cart.get(item._id);

    const quantity =
      existing
        ? existing.quantity
        : 0;

    if (!item.available) {
      const button =
        document.createElement('button');

      button.type = 'button';

      button.className =
        'add-btn';

      button.textContent =
        'Unavailable';

      button.disabled = true;

      wrapper.appendChild(button);

      return wrapper;
    }

    if (quantity === 0) {
      const button =
        document.createElement('button');

      button.type = 'button';

      button.className =
        'add-btn';

      button.textContent =
        'Add';

      button.addEventListener(
        'click',
        () => {
          state.cart.set(
            item._id,
            {
              product: item,
              quantity: 1,
            }
          );

          invalidateClientRequestId();

          renderProducts();
          updateCartBar();
        }
      );

      wrapper.appendChild(button);

      return wrapper;
    }

    const stepper =
      document.createElement('div');

    stepper.className =
      'qty-stepper';

    const minus =
      document.createElement('button');

    minus.type = 'button';

    minus.textContent = '−';

    minus.setAttribute(
      'aria-label',
      `Remove one ${item.name}`
    );

    minus.addEventListener(
      'click',
      () => {
        const line =
          state.cart.get(item._id);

        if (!line) return;

        if (line.quantity <= 1) {
          state.cart.delete(
            item._id
          );
        } else {
          line.quantity -= 1;
        }

        invalidateClientRequestId();

        renderProducts();
        updateCartBar();

        if (
          els.cartOverlay &&
          !els.cartOverlay.classList.contains(
            'hidden'
          )
        ) {
          renderCart();
        }
      }
    );

    const count =
      document.createElement('span');

    count.textContent =
      String(quantity);

    const plus =
      document.createElement('button');

    plus.type = 'button';

    plus.textContent = '+';

    plus.setAttribute(
      'aria-label',
      `Add one more ${item.name}`
    );

    plus.addEventListener(
      'click',
      () => {
        const line =
          state.cart.get(item._id);

        if (!line) return;

        if (line.quantity >= 50) {
          return;
        }

        line.quantity += 1;

        invalidateClientRequestId();

        renderProducts();
        updateCartBar();

        if (
          els.cartOverlay &&
          !els.cartOverlay.classList.contains(
            'hidden'
          )
        ) {
          renderCart();
        }
      }
    );

    stepper.appendChild(minus);
    stepper.appendChild(count);
    stepper.appendChild(plus);

    wrapper.appendChild(stepper);

    return wrapper;
  }

  /* =========================================================
     CART
     ========================================================= */

  function getCartSummary() {
    let total = 0;
    let count = 0;

    state.cart.forEach(
      (line) => {
        total +=
          Number(
            line.product.price || 0
          ) *
          line.quantity;

        count +=
          line.quantity;
      }
    );

    return {
      total,
      count,
    };
  }

  function updateCartBar() {
    if (!els.cartBar) return;

    const {
      total,
      count,
    } = getCartSummary();

    els.cartBar.classList.toggle(
      'hidden',
      count === 0
    );

    if (els.cartCount) {
      els.cartCount.textContent =
        count === 1
          ? '1 item'
          : `${count} items`;
    }

    if (els.cartBarTotal) {
      els.cartBarTotal.textContent =
        formatMoney(total);
    }
  }

  function renderCart() {
    if (!els.cartLines) return;

    els.cartLines.innerHTML = '';

    updatePaymentActions();

    const {
      total,
      count,
    } = getCartSummary();

    if (els.cartItemCount) {
      els.cartItemCount.textContent =
        String(count);
    }

    if (els.cartTotal) {
      els.cartTotal.textContent =
        formatMoney(total);
    }

    if (count === 0) {
      const empty =
        document.createElement('div');

      empty.className =
        'cart-empty';

      empty.textContent =
        'Your cart is empty.';

      els.cartLines.appendChild(
        empty
      );

      return;
    }

    state.cart.forEach(
      (line) => {
        const row =
          document.createElement('div');

        row.className =
          'cart-line';

        const left =
          document.createElement('div');

        left.className =
          'cart-line-left';

        const name =
          document.createElement('div');

        name.className =
          'cart-line-name';

        name.textContent =
          line.product.name;

        const price =
          document.createElement('div');

        price.className =
          'cart-line-price';

        price.textContent =
          `${formatMoney(
            line.product.price
          )} × ${line.quantity}`;

        const lineTotal =
          document.createElement('div');

        lineTotal.className =
          'cart-line-total';

        lineTotal.textContent =
          formatMoney(
            line.product.price *
              line.quantity
          );

        left.appendChild(name);
        left.appendChild(price);
        left.appendChild(lineTotal);

        const right =
          document.createElement('div');

        right.appendChild(
          renderQuantityControl(
            line.product
          )
        );

        row.appendChild(left);
        row.appendChild(right);

        els.cartLines.appendChild(
          row
        );
      }
    );

    updatePaymentActions();
  }

  /* =========================================================
     CART OPEN / CLOSE
     ========================================================= */

  function openCart() {
    if (state.cart.size === 0) {
      return;
    }

    renderCart();

    if (els.checkoutError) {
      els.checkoutError.classList.add(
        'hidden'
      );
    }

    els.cartOverlay.classList.remove(
      'hidden'
    );

    document.body.style.overflow =
      'hidden';
  }

  function closeCart() {
    if (!els.cartOverlay) return;

    els.cartOverlay.classList.add(
      'hidden'
    );

    document.body.style.overflow =
      '';
  }

  /* =========================================================
     PLACE ORDER
     ========================================================= */

  async function placeOrder() {
    if (state.cart.size === 0) {
      return;
    }

    const customerName =
      els.customerName.value.trim();

    const customerPhone =
      els.customerPhone.value.trim();

    if (
      !customerName &&
      !customerPhone
    ) {
      els.checkoutError.textContent =
        'Please enter your name or phone number before placing the order.';

      els.checkoutError.classList.remove(
        'hidden'
      );

      els.customerName.focus();

      return;
    }

    if (
      customerPhone &&
      !/^[0-9+\-\s]{6,20}$/.test(
        customerPhone
      )
    ) {
      els.checkoutError.textContent =
        'Please enter a valid phone number.';

      els.checkoutError.classList.remove(
        'hidden'
      );

      els.customerPhone.focus();

      return;
    }

    const {
      total,
    } = getCartSummary();

    if (total <= 0) {
      return;
    }

    els.checkoutError.classList.add(
      'hidden'
    );

    const selectedPayment =
      document.querySelector(
        'input[name="paymentMethod"]:checked'
      );

    const paymentMethod =
      selectedPayment?.value === 'upi'
        ? 'UPI'
        : 'CASH';

    /*
     * IMPORTANT:
     *
     * A customer order is never created for UPI here.
     *
     * If online payment is selected, the dedicated payment
     * handler below fails closed unless the real payment gateway
     * is configured and supported.
     */
    if (paymentMethod === 'UPI') {
      await startUpiPayment();
      return;
    }

    if (!state.clientRequestId) {
      state.clientRequestId =
        generateRequestId();
    }

    const items =
      Array.from(
        state.cart.values()
      ).map((line) => ({
        productId:
          line.product._id,
        quantity:
          line.quantity,
      }));

    const payload = {
      tableNumber:
        state.tableNumber,

      customerName:
        customerName || undefined,

      customerPhone:
        customerPhone || undefined,

      note:
        els.orderNote.value.trim() ||
        undefined,

      items,

      paymentMethod:
        'CASH',

      clientRequestId:
        state.clientRequestId,
    };

    els.placeOrderBtn.disabled =
      true;

    els.placeOrderBtn.textContent =
      'Placing order...';

    const success =
      await submitCreatedOrder(
        payload
      );

    els.placeOrderBtn.disabled =
      false;

    els.placeOrderBtn.textContent =
      'Place Order';

    if (!success) {
      return;
    }
  }

  /* =========================================================
     ONLINE PAYMENT
     ========================================================= */

  async function startUpiPayment() {
    if (state.cart.size === 0) return false;

    const customerName = els.customerName.value.trim();
    const customerPhone = els.customerPhone.value.trim();

    if (!customerName && !customerPhone) {
      els.checkoutError.textContent =
        'Please enter your name or phone number before paying.';
      els.checkoutError.classList.remove('hidden');
      els.customerName.focus();
      return false;
    }

    if (customerPhone && !/^[0-9+\-\s]{6,20}$/.test(customerPhone)) {
      els.checkoutError.textContent = 'Please enter a valid phone number.';
      els.checkoutError.classList.remove('hidden');
      els.customerPhone.focus();
      return false;
    }

    const upiId = String(state.paymentOptions.upiId || '').trim();
    if (state.paymentOptions.onlineUpi !== true || !upiId) {
      els.checkoutError.textContent =
        'Online UPI payment is not configured right now. Please choose Pay at Counter.';
      els.checkoutError.classList.remove('hidden');
      return false;
    }

    const { total } = getCartSummary();
    if (total <= 0) return false;

    if (!state.clientRequestId) {
      state.clientRequestId = generateRequestId();
    }

    const payload = {
      tableNumber: state.tableNumber,
      customerName: customerName || undefined,
      customerPhone: customerPhone || undefined,
      note: els.orderNote.value.trim() || undefined,
      items: Array.from(state.cart.values()).map((line) => ({
        productId: line.product._id,
        quantity: line.quantity,
      })),
      paymentMethod: 'UPI',
      clientRequestId: state.clientRequestId,
    };

    if (els.payUpiBtn) {
      els.payUpiBtn.disabled = true;
      els.payUpiBtn.textContent = 'Opening UPI...';
    }
    els.checkoutError.classList.add('hidden');

    try {
      // Create the QR order immediately with payment_initiated status. This
      // makes the attempt visible to staff even if the customer never returns
      // from the UPI application. It is never treated as paid automatically.
      const response = await apiRequest('/public/orders', {
        method: 'POST',
        body: JSON.stringify(payload),
      });

      const order = response.data || {};
      const orderNumber = order.orderNumber || '';
      const amount = Number(order.total ?? total).toFixed(2);
      const cafeName = state.paymentOptions.cafeName || 'FAST N FRESH CAFE';
      const transactionNote = `Order #${orderNumber} Table ${state.tableNumber}`;

      const upiUrl =
        `upi://pay?pa=${encodeURIComponent(upiId)}` +
        `&pn=${encodeURIComponent(cafeName)}` +
        `&am=${encodeURIComponent(amount)}` +
        `&cu=INR` +
        `&tn=${encodeURIComponent(transactionNote)}`;

      state.upiOrder = {
        orderId: order.orderId,
        token: order.trackingToken,
        orderNumber,
        tableNumber: order.tableNumber || state.tableNumber,
        tableName: order.tableName || state.tableName,
        total: Number(order.total ?? total),
        upiUrl,
      };

      try {
        localStorage.setItem(
          PENDING_UPI_ORDER_KEY,
          JSON.stringify(state.upiOrder)
        );
        setActiveUpiSession(true);
      } catch (_) {}

      showUpiPendingState();

      // This navigation is triggered by the customer's tap and hands off to
      // an installed UPI application on supported Android devices.
      window.location.assign(upiUrl);
      return true;
    } catch (error) {
      els.checkoutError.textContent =
        error.message || 'Could not start online payment. Please try again.';
      els.checkoutError.classList.remove('hidden');
      if (els.payUpiBtn) {
        els.payUpiBtn.disabled = false;
        els.payUpiBtn.textContent = 'PAY WITH UPI';
      }
      return false;
    }
  }

  function showUpiPendingState() {
    const order = state.upiOrder;
    if (!order || !els.upiPendingState) return;

    if (els.upiPendingTable) {
      els.upiPendingTable.textContent =
        `Table ${order.tableNumber || state.tableNumber}`;
    }
    if (els.upiPendingOrderNumber) {
      els.upiPendingOrderNumber.textContent = `#${order.orderNumber}`;
    }
    if (els.upiPendingTotal) {
      els.upiPendingTotal.textContent = formatMoney(order.total);
    }
    if (els.upiPendingHeading) {
      els.upiPendingHeading.textContent = 'Complete your UPI payment';
    }
    if (els.upiPendingSubtext) {
      els.upiPendingSubtext.textContent =
        'Complete the payment in your UPI app. Return to this page when done. The cafe will verify the payment before marking the order as paid.';
    }
    if (els.upiPendingStatusCard) {
      els.upiPendingStatusCard.classList.remove('hidden');
    }
    if (els.upiPendingStatusText) {
      els.upiPendingStatusText.textContent =
        'UPI payment started — waiting for cafe verification';
    }
    if (els.upiPendingError) {
      els.upiPendingError.classList.add('hidden');
    }
    if (els.upiReopenBtn) {
      els.upiReopenBtn.textContent = 'OPEN UPI AGAIN';
      els.upiReopenBtn.classList.remove('hidden');
    }
    if (els.upiCancelBtn) {
      els.upiCancelBtn.classList.remove('hidden');
    }

    showState('upiPendingState');
  }

  async function tryRestorePendingUpiOrder() {
    // localStorage survives QR scans/browser restarts. Only restore a UPI
    // attempt when this same browser session explicitly started it. A fresh
    // QR scan should always open the normal menu, not an old payment screen.
    if (!hasActiveUpiSession()) {
      try { localStorage.removeItem(PENDING_UPI_ORDER_KEY); } catch (_) {}
      state.upiOrder = null;
      return false;
    }

    let pending = null;
    try {
      const raw = localStorage.getItem(PENDING_UPI_ORDER_KEY);
      if (raw) pending = JSON.parse(raw);
    } catch (_) {}

    if (!pending || !pending.orderId || !pending.token || !pending.upiUrl) {
      try { localStorage.removeItem(PENDING_UPI_ORDER_KEY); } catch (_) {}
      setActiveUpiSession(false);
      return false;
    }

    // Never carry a payment attempt from another table into a newly scanned
    // table QR code.
    if (pending.tableNumber && String(pending.tableNumber) !== String(state.tableNumber)) {
      try { localStorage.removeItem(PENDING_UPI_ORDER_KEY); } catch (_) {}
      setActiveUpiSession(false);
      state.upiOrder = null;
      return false;
    }

    try {
      const response = await apiRequest(
        `/public/orders/${encodeURIComponent(pending.orderId)}/status?token=${encodeURIComponent(pending.token)}`
      );
      const data = response.data || {};

      if (data.status === 'voided' || data.paymentStatus === 'cancelled') {
        localStorage.removeItem(PENDING_UPI_ORDER_KEY);
        setActiveUpiSession(false);
        return false;
      }

      state.upiOrder = {
        ...pending,
        orderNumber: data.orderNumber || pending.orderNumber,
        tableNumber: data.tableNumber || pending.tableNumber,
        tableName: data.tableName || pending.tableName,
        total: Number(data.total ?? pending.total),
      };

      showUpiPendingState();
      return true;
    } catch (error) {
      // Invalid/expired tracking records should never trap the customer on
      // the payment screen. Temporary server/network failures may be kept.
      if ([400, 401, 403, 404].includes(error?.status)) {
        try { localStorage.removeItem(PENDING_UPI_ORDER_KEY); } catch (_) {}
        setActiveUpiSession(false);
        state.upiOrder = null;
        return false;
      }

      state.upiOrder = pending;
      showUpiPendingState();
      return true;
    }
  }

  function reopenPendingUpiPayment() {
    if (!state.upiOrder?.upiUrl) return;
    window.location.assign(state.upiOrder.upiUrl);
  }

  async function cancelPendingUpiPayment() {
    const order = state.upiOrder;
    if (!order?.orderId || !order?.token) return;

    if (els.upiCancelBtn) els.upiCancelBtn.disabled = true;
    if (els.upiPendingError) els.upiPendingError.classList.add('hidden');

    try {
      await apiRequest(
        `/public/orders/${encodeURIComponent(order.orderId)}/cancel?token=${encodeURIComponent(order.token)}`,
        { method: 'POST' }
      );

      state.upiOrder = null;
      state.clientRequestId = null;
      try { localStorage.removeItem(PENDING_UPI_ORDER_KEY); } catch (_) {}
      setActiveUpiSession(false);

      showState('app');
      openCart();
      if (els.checkoutError) {
        els.checkoutError.textContent =
          'Online payment cancelled. You can choose Pay at Counter.';
        els.checkoutError.classList.remove('hidden');
      }
      updatePaymentActions();
    } catch (error) {
      if (els.upiPendingError) {
        els.upiPendingError.textContent =
          error.message || 'Could not cancel this payment.';
        els.upiPendingError.classList.remove('hidden');
      }
    } finally {
      if (els.upiCancelBtn) els.upiCancelBtn.disabled = false;
    }
  }

  /* =========================================================
     CASH / NORMAL ORDER SUBMISSION
     ========================================================= */

  async function submitCreatedOrder(
    payload
  ) {
    try {
      const response =
        await apiRequest(
          '/public/orders',
          {
            method: 'POST',
            body: JSON.stringify(
              payload
            ),
          }
        );

      state.cart.clear();

      invalidateClientRequestId();

      closeCart();

      updateCartBar();

      if (els.successHeading) {
        els.successHeading.textContent =
          'Order placed!';
      }

      if (els.successSubtext) {
        els.successSubtext.textContent =
          'Your order has been sent to the cafe.';
      }

      if (els.successTable) {
        els.successTable.textContent =
          response.data.tableName ||
          `Table ${response.data.tableNumber}`;
      }

      if (els.successOrderNumber) {
        els.successOrderNumber.textContent =
          `#${response.data.orderNumber}`;
      }

      if (els.successTotal) {
        els.successTotal.textContent =
          formatMoney(
            response.data.total
          );
      }

      renderOrderItems(
        response.data.items
      );

      state.tracking.orderId =
        response.data.orderId;

      state.tracking.token =
        response.data.trackingToken;

      state.feedbackRating = 0;

      if (els.feedbackBox) {
        els.feedbackBox.classList.add(
          'hidden'
        );
      }

      if (els.feedbackMessage) {
        els.feedbackMessage.textContent =
          '';
      }

      startOrderTracking(
        response.data.orderId,
        response.data.trackingToken,
        response.data.status
      );

      try {
        localStorage.setItem(
          PENDING_ORDER_KEY,
          JSON.stringify({
            orderId:
              response.data.orderId,

            token:
              response.data.trackingToken,

            orderNumber:
              response.data.orderNumber,
          })
        );
      } catch (_) {}

      showState('successState');

      return true;
    } catch (error) {
      if (els.checkoutError) {
        els.checkoutError.textContent =
          error.message ||
          'Order failed. Please try again.';

        els.checkoutError.classList.remove(
          'hidden'
        );
      }

      return false;
    }
  }

  /* =========================================================
     PAYMENT ACTION BUTTONS
     ========================================================= */

  function updatePaymentActions() {
    const selected =
      document.querySelector(
        'input[name="paymentMethod"]:checked'
      );

    /*
     * Online UPI must be explicitly enabled by the backend.
     * A configured UPI ID alone is NOT enough.
     */
    const onlineUpiEnabled =
      state.paymentOptions.onlineUpi === true;

    const isUpi =
      selected?.value === 'upi' &&
      onlineUpiEnabled;

    if (els.payUpiBtn) {
      els.payUpiBtn.classList.toggle(
        'hidden',
        !isUpi
      );

      els.payUpiBtn.disabled =
        state.cart.size === 0;

      els.payUpiBtn.textContent =
        'PAY WITH UPI';
    }

    if (els.placeOrderBtn) {
      els.placeOrderBtn.classList.toggle(
        'hidden',
        isUpi
      );

      els.placeOrderBtn.textContent =
        'Place Order';
    }

    /*
     * If UPI has become unavailable while the customer is on the
     * checkout screen, do not leave the customer on a dead payment
     * option.
     */
    if (
      !onlineUpiEnabled &&
      selected?.value === 'upi'
    ) {
      const cashRadio =
        document.querySelector(
          'input[name="paymentMethod"][value="cash"], input[name="paymentMethod"][value="CASH"]'
        );

      if (cashRadio) {
        cashRadio.checked = true;
      }

      if (els.payUpiBtn) {
        els.payUpiBtn.classList.add(
          'hidden'
        );
      }

      if (els.placeOrderBtn) {
        els.placeOrderBtn.classList.remove(
          'hidden'
        );
      }
    }
  }

  /* =========================================================
     CUSTOMER ORDER TRACKING
     ========================================================= */

  function stopOrderTracking() {
    if (state.tracking.timer) {
      window.clearInterval(
        state.tracking.timer
      );

      state.tracking.timer = null;
    }
  }

  function orderStatusLabel(status) {
    switch (status) {
      case 'preparing':
        return 'Preparing your order';

      case 'ready':
        return 'Your order is ready';

      case 'completed':
        return 'Order completed';

      case 'voided':
        return 'Order cancelled';

      default:
        return 'Order received';
    }
  }

  function renderOrderStatus(status) {
    if (
      !els.successStatus ||
      !els.successStatusText
    ) {
      return;
    }

    const safe =
      status || 'open';

    els.successStatus.className =
      `order-status-card status-${safe}`;

    els.successStatusText.textContent =
      orderStatusLabel(safe);
  }

  async function refreshOrderStatus() {
    if (
      !state.tracking.orderId ||
      !state.tracking.token
    ) {
      return;
    }

    try {
      const response =
        await apiRequest(
          `/public/orders/${encodeURIComponent(
            state.tracking.orderId
          )}/status?token=${encodeURIComponent(
            state.tracking.token
          )}`
        );

      const data =
        response.data || {};

      state.tracking.status =
        data.status || 'open';

      renderOrderStatus(
        state.tracking.status
      );

      if (
        state.tracking.status ===
          'completed' ||
        state.tracking.status ===
          'voided'
      ) {
        stopOrderTracking();

        if (
          state.tracking.status ===
            'completed' &&
          els.feedbackBox
        ) {
          els.feedbackBox.classList.remove(
            'hidden'
          );
        }
      }
    } catch (_) {
      // Tracking is best-effort.
    }
  }

  function startOrderTracking(
    orderId,
    token,
    status
  ) {
    stopOrderTracking();

    state.tracking.orderId =
      orderId || null;

    state.tracking.token =
      token || null;

    state.tracking.status =
      status || 'open';

    renderOrderStatus(
      state.tracking.status
    );

    if (
      !state.tracking.orderId ||
      !state.tracking.token
    ) {
      return;
    }

    state.tracking.timer =
      window.setInterval(
        refreshOrderStatus,
        8000
      );
  }

  /* =========================================================
     EVENTS
     ========================================================= */

  if (els.cartBar) {
    els.cartBar.addEventListener(
      'click',
      openCart
    );
  }

  if (els.closeCart) {
    els.closeCart.addEventListener(
      'click',
      closeCart
    );
  }

  if (els.cartOverlay) {
    els.cartOverlay.addEventListener(
      'click',
      (event) => {
        if (
          event.target ===
          els.cartOverlay
        ) {
          closeCart();
        }
      }
    );
  }

  if (els.placeOrderBtn) {
    els.placeOrderBtn.addEventListener(
      'click',
      placeOrder
    );
  }

  if (els.payUpiBtn) {
    els.payUpiBtn.addEventListener(
      'click',
      startUpiPayment
    );
  }

  if (els.upiReopenBtn) {
    els.upiReopenBtn.addEventListener(
      'click',
      reopenPendingUpiPayment
    );
  }

  if (els.upiCancelBtn) {
    els.upiCancelBtn.addEventListener(
      'click',
      cancelPendingUpiPayment
    );
  }

  document
    .querySelectorAll(
      'input[name="paymentMethod"]'
    )
    .forEach((input) => {
      input.addEventListener(
        'change',
        () => {
          updatePaymentActions();
        }
      );
    });

  /* =========================================================
     FEEDBACK
     ========================================================= */

  if (els.feedbackStars) {
    els.feedbackStars
      .querySelectorAll('button')
      .forEach((button) => {
        button.addEventListener(
          'click',
          () => {
            state.feedbackRating =
              Number(
                button.dataset.rating ||
                  0
              );

            els.feedbackStars
              .querySelectorAll('button')
              .forEach((b) => {
                b.classList.toggle(
                  'selected',
                  Number(
                    b.dataset.rating ||
                      0
                  ) <=
                    state.feedbackRating
                );
              });
          }
        );
      });
  }

  if (els.submitFeedbackBtn) {
    els.submitFeedbackBtn.addEventListener(
      'click',
      async () => {
        if (
          !state.tracking.orderId ||
          !state.tracking.token ||
          !state.feedbackRating
        ) {
          els.feedbackMessage.textContent =
            'Please select a rating first.';

          return;
        }

        els.submitFeedbackBtn.disabled =
          true;

        try {
          await apiRequest(
            '/feedback',
            {
              method: 'POST',
              body: JSON.stringify({
                orderId:
                  state.tracking.orderId,

                token:
                  state.tracking.token,

                rating:
                  state.feedbackRating,

                comment:
                  els.feedbackComment.value.trim(),

                customerName:
                  els.customerName?.value?.trim() ||
                  '',
              }),
            }
          );

          els.feedbackMessage.textContent =
            'Thanks! Your feedback was received.';

          els.submitFeedbackBtn.textContent =
            'Feedback Sent';
        } catch (error) {
          els.feedbackMessage.textContent =
            error.message ||
            'Could not send feedback.';
        } finally {
          els.submitFeedbackBtn.disabled =
            false;
        }
      }
    );
  }

  /* =========================================================
     SEARCH EVENTS
     ========================================================= */

  if (els.searchInput) {
    els.searchInput.addEventListener(
      'input',
      () => {
        state.searchQuery =
          els.searchInput.value;

        updateSearchUI();
        renderProducts();
      }
    );
  }

  function clearSearch() {
    if (!els.searchInput) return;

    els.searchInput.value = '';

    state.searchQuery = '';

    updateSearchUI();
    renderProducts();

    els.searchInput.focus();
  }

  if (els.clearSearch) {
    els.clearSearch.addEventListener(
      'click',
      clearSearch
    );
  }

  if (els.clearSearchBtn) {
    els.clearSearchBtn.addEventListener(
      'click',
      clearSearch
    );
  }

  /* =========================================================
     RETRY
     ========================================================= */

  if (els.retryBtn) {
    els.retryBtn.addEventListener(
      'click',
      () => {
        init();
      }
    );
  }

  /* =========================================================
     DONE
     ========================================================= */

  if (els.doneBtn) {
    els.doneBtn.addEventListener(
      'click',
      () => {
        setActiveUpiSession(false);
        stopOrderTracking();

        state.tracking.orderId =
          null;

        state.tracking.token =
          null;

        clearPendingOrder();

        window.location.reload();
      }
    );
  }

  /* =========================================================
     ESC
     ========================================================= */

  document.addEventListener(
    'keydown',
    (event) => {
      if (
        event.key === 'Escape' &&
        els.cartOverlay &&
        !els.cartOverlay.classList.contains(
          'hidden'
        )
      ) {
        closeCart();
      }
    }
  );

  /* =========================================================
     START
     ========================================================= */

  init();
})();
