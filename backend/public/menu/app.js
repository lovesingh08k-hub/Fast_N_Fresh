(function () {
  'use strict';

  const API_BASE_URL =
    (window.FNF_CONFIG && window.FNF_CONFIG.API_BASE_URL) || '';

  // Deliberately not defaulted to true: an operator must explicitly flip
  // this in config.js after confirming API_BASE_URL is reachable and
  // correct (see the instructions in config.js). This turns an unverified
  // guess into a hard stop instead of a silent failure in production.
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

    checkoutError: document.getElementById('checkoutError'),
    placeOrderBtn: document.getElementById('placeOrderBtn'),

    upiPendingState: document.getElementById('upiPendingState'),
    upiPendingHeading: document.getElementById('upiPendingHeading'),
    upiPendingTable: document.getElementById('upiPendingTable'),
    upiPendingOrderNumber: document.getElementById('upiPendingOrderNumber'),
    upiPendingTotal: document.getElementById('upiPendingTotal'),
    upiReopenBtn: document.getElementById('upiReopenBtn'),
    upiPendingError: document.getElementById('upiPendingError'),
    upiPendingStatusText: document.getElementById('upiPendingStatusText'),
    upiCancelBtn: document.getElementById('upiCancelBtn'),
  };

  const state = {
    paymentOptions: { onlineUpi: false, upiId: '', cafeName: 'FAST N FRESH CAFE' },
    tableNumber: null,
    tableName: null,

    categories: [],
    items: [],

    activeCategory: 'all',
    searchQuery: '',

    cart: new Map(),

    loading: false,

    // Generated the first time "Place Order" is attempted for the current
    // cart, and reused on retries (e.g. a network blip or a slow response
    // the customer taps through again) so a resend can't create a second
    // order. Cleared whenever the cart itself changes or an order
    // succeeds, since that means a genuinely new order is being started.
    clientRequestId: null,
    tracking: { orderId: null, token: null, timer: null, status: null },
    feedbackRating: 0,
    // Holds only the provider payment transaction while online payment is
    // processing. No final Order exists until the backend verifies payment.
    // Shape: { transactionId, token, tableName, tableNumber, total,
    // providerPaymentId, checkoutUrl, pollTimer }
    upiOrder: null,
  };

  function generateRequestId() {
    if (window.crypto && typeof window.crypto.randomUUID === 'function') {
      return window.crypto.randomUUID();
    }
    // Fallback UUID v4 for browsers/contexts without crypto.randomUUID
    // (e.g. non-HTTPS local development).
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
      const r = (Math.random() * 16) | 0;
      const v = c === 'x' ? r : (r & 0x3) | 0x8;
      return v.toString(16);
    });
  }

  function invalidateClientRequestId() {
    state.clientRequestId = null;
  }

  /* =========================================================
     HELPERS
     ========================================================= */

  function formatMoney(value) {
    return '₹' + Number(value || 0).toLocaleString('en-IN', {
      maximumFractionDigits: 2,
    });
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
    if (els.loadingSlowHint) els.loadingSlowHint.classList.add('hidden');
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
    els.errorTitle.textContent = title;
    els.errorMessage.textContent = message;
    showState('errorState');
  }

  async function apiRequest(path, options = {}) {
    if (
      !API_BASE_URL ||
      API_BASE_URL.includes('your-deployed-api-domain.com')
    ) {
      throw new Error(
        'Cafe menu is not configured correctly.'
      );
    }

    if (!API_BASE_URL_VERIFIED) {
      throw new Error(
        'This menu has not been confirmed to be connected to the ' +
        'right server yet. Please ask staff, or see the instructions ' +
        'in config.js.'
      );
    }

    let response;
    const controller = new AbortController();
    const timeoutId = window.setTimeout(() => controller.abort(), 15000);

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
      if (error?.name === 'AbortError') {
        throw new Error(
          'Cafe server took too long to respond. Please try again.'
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
    } catch {
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
     RETURNING CUSTOMER — RESTORE A PENDING ORDER
     ========================================================= */

  const PENDING_ORDER_KEY = 'fnf_last_order';
  const PENDING_UPI_KEY = 'fnf_pending_upi_payment';

  function clearPendingOrder() {
    try {
      localStorage.removeItem(PENDING_ORDER_KEY);
    } catch (_) {}
  }

  function readPendingOrder() {
    try {
      const raw = localStorage.getItem(PENDING_ORDER_KEY);
      if (!raw) return null;

      const parsed = JSON.parse(raw);

      if (!parsed || !parsed.orderId || !parsed.token) {
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
      const row = document.createElement('div');
      row.className = 'success-item-row';

      const nameWrap = document.createElement('span');
      nameWrap.className = 'success-item-name';

      const qty = document.createElement('span');
      qty.className = 'success-item-qty';
      qty.textContent = `${item.quantity}× `;

      nameWrap.appendChild(qty);
      nameWrap.appendChild(
        document.createTextNode(item.name || '')
      );

      const price = document.createElement('span');
      price.className = 'success-item-price';

      const lineTotal =
        item.total != null
          ? item.total
          : (item.price || 0) * (item.quantity || 1);

      price.textContent = formatMoney(lineTotal);

      row.appendChild(nameWrap);
      row.appendChild(price);

      els.successItems.appendChild(row);
    });
  }

  // If the customer closes the tab (or the page reloads) after ordering,
  // this restores their order tracking view instead of dropping them back
  // into an empty menu with no memory of what they ordered.
  async function tryRestorePendingOrder() {
    const pending = readPendingOrder();
    if (!pending) return false;

    try {
      const response = await apiRequest(
        `/public/orders/${encodeURIComponent(pending.orderId)}/status?token=${encodeURIComponent(pending.token)}`
      );

      const data = response.data || {};

      if (data.status === 'voided') {
        clearPendingOrder();
        return false;
      }

      if (els.successHeading) {
        els.successHeading.textContent = 'Welcome back!';
      }

      if (els.successSubtext) {
        els.successSubtext.textContent =
          "Here's your order from this table.";
      }

      els.successTable.textContent =
        data.tableName || `Table ${data.tableNumber}`;

      els.successOrderNumber.textContent =
        `#${data.orderNumber}`;

      els.successTotal.textContent =
        formatMoney(data.total);

      renderOrderItems(data.items);

      state.feedbackRating = 0;
      els.feedbackBox.classList.add('hidden');
      els.feedbackMessage.textContent = '';

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

      const [menuResponse, paymentResponse] = await Promise.all([
        apiRequest('/public/menu'),
        apiRequest('/public/payment-options'),
      ]);

      state.categories =
        menuResponse.categories || [];

      state.items =
        menuResponse.items || [];

      state.paymentOptions = paymentResponse.data || state.paymentOptions;
      const configuredUpiId = String(state.paymentOptions.upiId || '').trim();
      const onlineUpiEnabled = Boolean(state.paymentOptions.onlineUpi || configuredUpiId);
      state.paymentOptions.upiId = configuredUpiId;
      state.paymentOptions.onlineUpi = onlineUpiEnabled;
      if (els.onlinePaymentOption) {
        els.onlinePaymentOption.style.display = onlineUpiEnabled ? 'flex' : 'none';
      }
      if (els.upiHelpText) {
        els.upiHelpText.style.display = onlineUpiEnabled ? 'block' : 'none';
      }
      updatePaymentActions();

      renderApp();

      // Always show the menu first. An old/stale order-status request must
      // never block the customer from seeing the menu.
      showState('app');
      setTimeout(maybeResumePendingUpiPayment, 350);

      const restored = await tryRestorePendingOrder();
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

    els.tableBadge.textContent =
      `Table ${tableNumber}`;
  }

  /* =========================================================
     CATEGORIES
     ========================================================= */

  function renderCategories() {
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
          String(item.categoryName || '')
            .toLowerCase();

        return (
          name.includes(query) ||
          category.includes(query)
        );
      }
    );
  }

  function updateSearchUI() {
    const hasSearch =
      state.searchQuery.trim().length > 0;

    els.clearSearch.classList.toggle(
      'hidden',
      !hasSearch
    );
  }

  /* =========================================================
     PRODUCTS
     ========================================================= */

  function renderProducts() {
    els.productList.innerHTML = '';

    const filteredItems =
      getFilteredItems();

    if (filteredItems.length === 0) {
      els.productList.classList.add(
        'hidden'
      );

      els.searchEmpty.classList.remove(
        'hidden'
      );

      return;
    }

    els.productList.classList.remove(
      'hidden'
    );

    els.searchEmpty.classList.add(
      'hidden'
    );

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
      (products, categoryName) => {
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

    /* IMAGE */

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
        image.style.display = 'none';
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

    /* INFO */

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

    /* ACTION */

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

    /* MINUS */

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
          !els.cartOverlay.classList.contains(
            'hidden'
          )
        ) {
          renderCart();
        }
      }
    );

    /* COUNT */

    const count =
      document.createElement('span');

    count.textContent =
      String(quantity);

    /* PLUS */

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
          Number(line.product.price || 0) *
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
    const {
      total,
      count,
    } = getCartSummary();

    els.cartBar.classList.toggle(
      'hidden',
      count === 0
    );

    els.cartCount.textContent =
      count === 1
        ? '1 item'
        : `${count} items`;

    els.cartBarTotal.textContent =
      formatMoney(total);
  }

  function renderCart() {
    els.cartLines.innerHTML = '';
    updatePaymentActions();

    const {
      total,
      count,
    } = getCartSummary();

    els.cartItemCount.textContent =
      String(count);

    els.cartTotal.textContent =
      formatMoney(total);

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

    els.checkoutError.classList.add(
      'hidden'
    );

    els.cartOverlay.classList.remove(
      'hidden'
    );

    document.body.style.overflow =
      'hidden';
  }

  function closeCart() {
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
    if (state.cart.size === 0) return;

    const customerName = els.customerName.value.trim();
    const customerPhone = els.customerPhone.value.trim();

    if (!customerName && !customerPhone) {
      els.checkoutError.textContent = 'Please enter your name or phone number before placing the order.';
      els.checkoutError.classList.remove('hidden');
      els.customerName.focus();
      return;
    }
    if (customerPhone && !/^[0-9+\-\s]{6,20}$/.test(customerPhone)) {
      els.checkoutError.textContent = 'Please enter a valid phone number.';
      els.checkoutError.classList.remove('hidden');
      els.customerPhone.focus();
      return;
    }

    const { total } = getCartSummary();
    if (total <= 0) return;

    els.checkoutError.classList.add('hidden');
    const selectedPayment = document.querySelector('input[name="paymentMethod"]:checked');
    const paymentMethod = selectedPayment?.value === 'upi' ? 'UPI' : 'CASH';

    // Pay-with-UPI is a separate, dedicated button/flow (see startUpiPayment)
    // because it creates the order immediately and hands off to a UPI app.
    // "Place Order" here only ever handles Pay-at-Counter (CASH).
    if (paymentMethod === 'UPI') {
      await startUpiPayment();
      return;
    }

    if (!state.clientRequestId) state.clientRequestId = generateRequestId();

    const items = Array.from(state.cart.values()).map((line) => ({
      productId: line.product._id,
      quantity: line.quantity,
    }));

    const payload = {
      tableNumber: state.tableNumber,
      customerName: customerName || undefined,
      customerPhone: customerPhone || undefined,
      note: els.orderNote.value.trim() || undefined,
      items,
      paymentMethod: 'CASH',
      clientRequestId: state.clientRequestId,
    };

    els.placeOrderBtn.disabled = true;
    els.placeOrderBtn.textContent = 'Placing order...';
    await submitCreatedOrder(payload);
    els.placeOrderBtn.disabled = false;
    els.placeOrderBtn.textContent = 'Place Order';
  }

  // Online payments are provider-backed. The customer page never creates an
  // Order and never treats an external-app handoff as proof of payment.
  function openPaymentProvider(payment) {
    const url = String(payment?.checkoutUrl || '').trim();
    if (!url) {
      if (els.upiPendingError) {
        els.upiPendingError.textContent =
          'The payment provider did not return a checkout link. Please try again.';
        els.upiPendingError.classList.remove('hidden');
      }
      return false;
    }
    try {
      window.location.href = url;
      return true;
    } catch (_) {
      if (els.upiPendingError) {
        els.upiPendingError.textContent = 'Could not open the payment screen. Please try again.';
        els.upiPendingError.classList.remove('hidden');
      }
      return false;
    }
  }

  function renderUpiPendingScreen(payment) {
    if (els.upiPendingTable) els.upiPendingTable.textContent =
      payment.tableName || `Table ${payment.tableNumber}`;
    if (els.upiPendingOrderNumber) els.upiPendingOrderNumber.textContent =
      `Payment ${payment.providerPaymentId || payment.transactionId}`;
    if (els.upiPendingTotal) els.upiPendingTotal.textContent = formatMoney(payment.total);
    if (els.upiPendingStatusText) els.upiPendingStatusText.textContent =
      'Payment processing...';
    if (els.upiPendingError) els.upiPendingError.classList.add('hidden');
  }

  function saveUpiOrderToStorage() {
    if (!state.upiOrder) return;
    try {
      const { pollTimer, ...toStore } = state.upiOrder;
      localStorage.setItem(PENDING_UPI_KEY, JSON.stringify(toStore));
    } catch (_) {}
  }

  function stopUpiPolling() {
    if (state.upiOrder && state.upiOrder.pollTimer) {
      window.clearInterval(state.upiOrder.pollTimer);
      state.upiOrder.pollTimer = null;
    }
  }

  function clearUpiOrder() {
    stopUpiPolling();
    state.upiOrder = null;
    try { localStorage.removeItem(PENDING_UPI_KEY); } catch (_) {}
  }

  async function resolveSuccessfulPayment(data, paymentInfo) {
    if (!data?.orderId) return false;
    const orderId = data.orderId;
    clearUpiOrder();
    state.cart.clear();
    invalidateClientRequestId();
    closeCart();
    updateCartBar();
    if (els.successHeading) els.successHeading.textContent = 'Payment successful!';
    if (els.successSubtext) els.successSubtext.textContent =
      'Your payment was verified and your order has been sent to the cafe.';
    els.successTable.textContent = data.tableName || paymentInfo.tableName || `Table ${paymentInfo.tableNumber}`;
    els.successOrderNumber.textContent = `#${data.orderNumber}`;
    els.successTotal.textContent = formatMoney(data.total);
    renderOrderItems(data.items || []);
    state.feedbackRating = 0;
    els.feedbackBox.classList.add('hidden');
    els.feedbackMessage.textContent = '';
    startOrderTracking(orderId, data.trackingToken, data.status);
    try {
      localStorage.setItem(PENDING_ORDER_KEY, JSON.stringify({
        orderId,
        token: data.trackingToken,
        orderNumber: data.orderNumber,
      }));
    } catch (_) {}
    showState('successState');
    return true;
  }

  // Polls the provider-backed payment transaction. The server is the only
  // authority allowed to turn a payment into a final Order.
  function startUpiPolling() {
    stopUpiPolling();
    if (!state.upiOrder) return;

    const poll = async () => {
      if (!state.upiOrder) return;
      try {
        const response = await apiRequest(
          `/public/payments/${encodeURIComponent(state.upiOrder.transactionId)}/status?token=${encodeURIComponent(state.upiOrder.token)}`
        );
        const data = response.data || {};
        const status = String(data.status || '').toLowerCase();

        if (status === 'succeeded' && data.orderId) {
          const paymentInfo = { ...state.upiOrder };
          try {
            const orderResponse = await apiRequest(
              `/public/orders/${encodeURIComponent(data.orderId)}/status?token=${encodeURIComponent(paymentInfo.token)}`
            );
            const orderData = orderResponse.data || {};
            await resolveSuccessfulPayment({
              orderId: data.orderId,
              orderNumber: orderData.orderNumber,
              tableName: orderData.tableName,
              total: orderData.total,
              items: orderData.items,
              status: orderData.status,
              trackingToken: paymentInfo.token,
            }, paymentInfo);
          } catch (_) {
            // Do not show payment success without the final server-side Order.
          }
          return;
        }

        if (['failed', 'cancelled', 'expired'].includes(status)) {
          const message = status === 'cancelled'
            ? 'Payment cancelled. Your order was not placed.'
            : status === 'expired'
              ? 'Payment expired. Your order was not placed.'
              : 'Payment failed. Your order was not placed.';
          if (els.upiPendingStatusText) els.upiPendingStatusText.textContent = message;
          if (els.upiPendingError) {
            els.upiPendingError.textContent = 'No order was created. You can return to the cart and try again.';
            els.upiPendingError.classList.remove('hidden');
          }
          stopUpiPolling();
          return;
        }

        if (els.upiPendingStatusText) els.upiPendingStatusText.textContent = 'Payment processing...';
      } catch (_) {
        // Best-effort polling. A temporary network error never becomes
        // payment success.
      }
    };

    state.upiOrder.pollTimer = window.setInterval(poll, 4000);
    poll();
  }

  async function startUpiPayment() {
    if (state.cart.size === 0) return;

    const customerName = els.customerName.value.trim();
    const customerPhone = els.customerPhone.value.trim();

    if (!customerName && !customerPhone) {
      els.checkoutError.textContent = 'Please enter your name or phone number before paying.';
      els.checkoutError.classList.remove('hidden');
      els.customerName.focus();
      return;
    }
    if (customerPhone && !/^[0-9+\-\s]{6,20}$/.test(customerPhone)) {
      els.checkoutError.textContent = 'Please enter a valid phone number.';
      els.checkoutError.classList.remove('hidden');
      els.customerPhone.focus();
      return;
    }

    const { total } = getCartSummary();
    if (total <= 0) return;
    if (!state.clientRequestId) state.clientRequestId = generateRequestId();

    const payload = {
      tableNumber: state.tableNumber,
      customerName: customerName || undefined,
      customerPhone: customerPhone || undefined,
      note: els.orderNote.value.trim() || undefined,
      items: Array.from(state.cart.values()).map((line) => ({
        productId: line.product._id,
        quantity: line.quantity,
      })),
      clientRequestId: state.clientRequestId,
    };

    if (els.payUpiBtn) {
      els.payUpiBtn.disabled = true;
      els.payUpiBtn.textContent = 'Starting payment...';
    }
    els.checkoutError.classList.add('hidden');

    try {
      const response = await apiRequest('/public/payments', {
        method: 'POST',
        body: JSON.stringify(payload),
      });
      const data = response.data || {};

      state.upiOrder = {
        transactionId: data.transactionId,
        token: state.clientRequestId,
        tableName: state.tableName,
        tableNumber: state.tableNumber,
        total,
        providerPaymentId: data.providerPaymentId || null,
        checkoutUrl: data.checkoutUrl || null,
        pollTimer: null,
      };
      saveUpiOrderToStorage();
      closeCart();
      updateCartBar();
      renderUpiPendingScreen(state.upiOrder);
      showState('upiPendingState');

      if (data.status === 'succeeded' && data.orderId) {
        await startUpiPolling();
      } else {
        openPaymentProvider(data);
        startUpiPolling();
      }
    } catch (error) {
      // A failed payment start is not an order. Clear the attempt id so the
      // customer can make a fresh attempt without creating a duplicate.
      invalidateClientRequestId();
      els.checkoutError.textContent =
        error.message || 'Online payment is not available right now. Please choose Pay at Counter.';
      els.checkoutError.classList.remove('hidden');
    } finally {
      if (els.payUpiBtn) {
        els.payUpiBtn.disabled = false;
        els.payUpiBtn.textContent = 'PAY ONLINE';
      }
    }
  }

  async function cancelUpiOrder() {
    if (!state.upiOrder) return;
    const orderInfo = state.upiOrder;
    if (els.upiCancelBtn) els.upiCancelBtn.disabled = true;
    try {
      await apiRequest(`/public/payments/${encodeURIComponent(orderInfo.transactionId)}/cancel`, {
        method: 'POST',
        body: JSON.stringify({ token: orderInfo.token }),
      });
      clearUpiOrder();
      showState('app');
    } catch (error) {
      if (els.upiPendingError) {
        els.upiPendingError.textContent =
          error.message || 'Could not cancel this payment attempt.';
        els.upiPendingError.classList.remove('hidden');
      }
    } finally {
      if (els.upiCancelBtn) els.upiCancelBtn.disabled = false;
    }
  }

  async function submitCreatedOrder(payload) {
    try {
      const response = await apiRequest('/public/orders', {
        method: 'POST',
        body: JSON.stringify(payload),
      });

      state.cart.clear();
      invalidateClientRequestId();

      closeCart();
      updateCartBar();

      if (els.successHeading) els.successHeading.textContent = 'Order placed!';
      if (els.successSubtext) els.successSubtext.textContent = 'Your order has been sent to the cafe.';
      els.successTable.textContent = response.data.tableName || `Table ${response.data.tableNumber}`;
      els.successOrderNumber.textContent = `#${response.data.orderNumber}`;
      els.successTotal.textContent = formatMoney(response.data.total);
      if (typeof renderOrderItems === 'function') renderOrderItems(response.data.items);

      if (true) {
        state.tracking.orderId = response.data.orderId;
        state.tracking.token = response.data.trackingToken;
        state.feedbackRating = 0;
        els.feedbackBox.classList.add('hidden');
        els.feedbackMessage.textContent = '';
        startOrderTracking(response.data.orderId, response.data.trackingToken, response.data.status);
        try { localStorage.setItem(PENDING_ORDER_KEY, JSON.stringify({ orderId: response.data.orderId, token: response.data.trackingToken, orderNumber: response.data.orderNumber })); } catch (_) {}
      }

      showState('successState');
      return true;
    } catch (error) {
      els.checkoutError.textContent = error.message || 'Order failed. Please try again.';
      els.checkoutError.classList.remove('hidden');
      return false;
    }
  }

  // On reload/resume, only restore an unfinished payment transaction. The
  // browser never promotes it to an Order.
  let upiResumeBusy = false;

  async function maybeResumePendingUpiPayment() {
    if (upiResumeBusy || state.upiOrder) return;
    let saved = null;
    try {
      const raw = localStorage.getItem(PENDING_UPI_KEY);
      if (raw) saved = JSON.parse(raw);
    } catch (_) {}
    if (!saved || !saved.transactionId || !saved.token) return;

    upiResumeBusy = true;
    try {
      const response = await apiRequest(
        `/public/payments/${encodeURIComponent(saved.transactionId)}/status?token=${encodeURIComponent(saved.token)}`
      );
      const data = response.data || {};
      if (data.status === 'succeeded' && data.orderId) {
        clearUpiOrder();
        const orderResponse = await apiRequest(
          `/public/orders/${encodeURIComponent(data.orderId)}/status?token=${encodeURIComponent(saved.token)}`
        );
        const orderData = orderResponse.data || {};
        await resolveSuccessfulPayment({
          orderId: data.orderId,
          orderNumber: orderData.orderNumber,
          tableName: orderData.tableName,
          total: orderData.total,
          items: orderData.items,
          status: orderData.status,
          trackingToken: saved.token,
        }, saved);
        return;
      }

      if (['failed', 'cancelled', 'expired'].includes(String(data.status || '').toLowerCase())) {
        try { localStorage.removeItem(PENDING_UPI_KEY); } catch (_) {}
        return;
      }

      state.upiOrder = {
        ...saved,
        pollTimer: null,
      };
      renderUpiPendingScreen(state.upiOrder);
      showState('upiPendingState');
      startUpiPolling();
    } catch (_) {
      // If the transaction cannot be resolved, discard only the local draft.
      // A localStorage value can never create or mark an Order paid.
      try { localStorage.removeItem(PENDING_UPI_KEY); } catch (_) {}
    } finally {
      upiResumeBusy = false;
    }
  }

  function updatePaymentActions() {
    const selected = document.querySelector('input[name="paymentMethod"]:checked');
    const isUpi = selected?.value === 'upi';
    if (els.payUpiBtn) {
      els.payUpiBtn.classList.toggle('hidden', !isUpi);
      els.payUpiBtn.disabled = state.cart.size === 0;
      els.payUpiBtn.textContent = 'PAY ONLINE';
    }
    if (els.placeOrderBtn) {
      els.placeOrderBtn.classList.toggle('hidden', isUpi);
      els.placeOrderBtn.textContent = 'Place Order';
    }
  }

  /* =========================================================
     CUSTOMER ORDER TRACKING
     ========================================================= */

  function stopOrderTracking() {
    if (state.tracking.timer) {
      window.clearInterval(state.tracking.timer);
      state.tracking.timer = null;
    }
  }

  function orderStatusLabel(status) {
    switch (status) {
      case 'preparing': return 'Preparing your order';
      case 'ready': return 'Your order is ready';
      case 'completed': return 'Order completed';
      case 'voided': return 'Order cancelled';
      default: return 'Order received';
    }
  }

  function renderOrderStatus(status) {
    if (!els.successStatus || !els.successStatusText) return;
    const safe = status || 'open';
    els.successStatus.className = `order-status-card status-${safe}`;
    els.successStatusText.textContent = orderStatusLabel(safe);
  }

  async function refreshOrderStatus() {
    if (!state.tracking.orderId || !state.tracking.token) return;
    try {
      const response = await apiRequest(
        `/public/orders/${encodeURIComponent(state.tracking.orderId)}/status?token=${encodeURIComponent(state.tracking.token)}`
      );
      const data = response.data || {};
      state.tracking.status = data.status || 'open';
      renderOrderStatus(state.tracking.status);

      if (state.tracking.status === 'completed' || state.tracking.status === 'voided') {
        stopOrderTracking();
        if (state.tracking.status === 'completed' && els.feedbackBox) els.feedbackBox.classList.remove('hidden');
      }
    } catch (_) {
      // Tracking is best-effort; keep the last known status visible.
    }
  }

  function startOrderTracking(orderId, token, status) {
    stopOrderTracking();
    state.tracking.orderId = orderId || null;
    state.tracking.token = token || null;
    state.tracking.status = status || 'open';
    renderOrderStatus(state.tracking.status);
    if (!state.tracking.orderId || !state.tracking.token) return;
    state.tracking.timer = window.setInterval(refreshOrderStatus, 8000);
  }

  /* =========================================================
     EVENTS
     ========================================================= */

  els.cartBar.addEventListener(
    'click',
    openCart
  );

  els.closeCart.addEventListener(
    'click',
    closeCart
  );

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

  els.placeOrderBtn.addEventListener(
    'click',
    placeOrder
  );

  if (els.payUpiBtn) {
    els.payUpiBtn.addEventListener('click', startUpiPayment);
  }

  if (els.upiReopenBtn) {
    els.upiReopenBtn.addEventListener('click', () => {
      if (state.upiOrder) openPaymentProvider(state.upiOrder);
    });
  }

  if (els.upiCancelBtn) {
    els.upiCancelBtn.addEventListener('click', cancelUpiOrder);
  }

  document.querySelectorAll('input[name="paymentMethod"]').forEach((input) => {
    input.addEventListener('change', () => {
      updatePaymentActions();
    });
  });

  if (els.feedbackStars) {
    els.feedbackStars.querySelectorAll('button').forEach((button) => {
      button.addEventListener('click', () => {
        state.feedbackRating = Number(button.dataset.rating || 0);
        els.feedbackStars.querySelectorAll('button').forEach((b) => b.classList.toggle('selected', Number(b.dataset.rating || 0) <= state.feedbackRating));
      });
    });
  }

  if (els.submitFeedbackBtn) {
    els.submitFeedbackBtn.addEventListener('click', async () => {
      if (!state.tracking.orderId || !state.tracking.token || !state.feedbackRating) {
        els.feedbackMessage.textContent = 'Please select a rating first.';
        return;
      }
      els.submitFeedbackBtn.disabled = true;
      try {
        await apiRequest('/feedback', { method: 'POST', body: JSON.stringify({ orderId: state.tracking.orderId, token: state.tracking.token, rating: state.feedbackRating, comment: els.feedbackComment.value.trim(), customerName: els.customerName?.value?.trim() || '' }) });
        els.feedbackMessage.textContent = 'Thanks! Your feedback was received.';
        els.submitFeedbackBtn.textContent = 'Feedback Sent';
      } catch (error) { els.feedbackMessage.textContent = error.message || 'Could not send feedback.'; }
      finally { els.submitFeedbackBtn.disabled = false; }
    });
  }

  /* SEARCH */

  els.searchInput.addEventListener(
    'input',
    () => {
      state.searchQuery =
        els.searchInput.value;

      updateSearchUI();
      renderProducts();
    }
  );

  function clearSearch() {
    els.searchInput.value = '';

    state.searchQuery = '';

    updateSearchUI();
    renderProducts();

    els.searchInput.focus();
  }

  els.clearSearch.addEventListener(
    'click',
    clearSearch
  );

  els.clearSearchBtn.addEventListener(
    'click',
    clearSearch
  );

  /* RETRY */

  els.retryBtn.addEventListener(
    'click',
    () => {
      init();
    }
  );

  /* DONE */

  els.doneBtn.addEventListener(
    'click',
    () => {
      stopOrderTracking();
      state.tracking.orderId = null;
      state.tracking.token = null;
      clearPendingOrder();
      window.location.reload();
    }
  );

  /* ESC */

  document.addEventListener(
    'keydown',
    (event) => {
      if (
        event.key === 'Escape' &&
        !els.cartOverlay.classList.contains(
          'hidden'
        )
      ) {
        closeCart();
      }
    }
  );

  window.addEventListener('pageshow', () => {
    setTimeout(maybeResumePendingUpiPayment, 350);
  });

  document.addEventListener('visibilitychange', () => {
    if (document.visibilityState === 'visible') {
      setTimeout(maybeResumePendingUpiPayment, 350);
    }
  });

  /* START */

  init();
})();