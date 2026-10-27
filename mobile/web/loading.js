// Hides the HTML loading screen once Flutter has drawn its first frame.
// Kept in a file (not inline) so the page works under the server's
// script-src 'self' Content-Security-Policy.
window.addEventListener('flutter-first-frame', function () {
  var loading = document.getElementById('loading');
  if (loading) loading.remove();
});
