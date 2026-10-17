for (const button of document.querySelectorAll('button')) {
  button.addEventListener('click', async () => {
    document.querySelectorAll('button').forEach(item => { item.disabled = true; });
    document.querySelector('#message').textContent = button.id === 'capture' ? 'Capturing the visible page…' : 'Opening your inbox…';
    try {
      const result = await chrome.runtime.sendMessage({ action: button.id });
      if (result?.error) throw new Error(result.error);
      window.close();
    } catch (error) {
      document.querySelector('#message').textContent = error.message;
      document.querySelectorAll('button').forEach(item => { item.disabled = false; });
    }
  });
}
