export const copyToClipboard = (text: string) => {
  if (navigator.clipboard) {
    navigator.clipboard.writeText(text).catch(err => {
      console.error('Failed to copy: ', err);
    });
  } else {
    // Fallback for older browsers
    const textarea = document.createElement('textarea');
    textarea.value = text;
    document.body.appendChild(textarea);
    textarea.select();
    document.execCommand('copy');
    document.body.removeChild(textarea);
  }
}; 