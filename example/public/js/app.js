// D_Server App JavaScript
document.addEventListener('DOMContentLoaded', function() {
  console.log('D_Server app loaded successfully!');

  // Add simple interactivity
  const buttons = document.querySelectorAll('.btn');
  buttons.forEach(button => {
    button.addEventListener('click', function(e) {
      console.log('Button clicked:', this.textContent);
    });
  });
});
