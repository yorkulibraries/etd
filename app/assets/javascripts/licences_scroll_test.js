
/* Jquery function to ensure user has scrolled through the licence before they can check the "I agree ..." */
$(document).ready(function() {
  // Disable checkboxes only if they are not already checked
  if (!$('#thesis_yorkspace_licence_agreement').is(':checked')) {
    $('#thesis_yorkspace_licence_agreement').prop('disabled', true);
  }

  if (!$('#thesis_etd_licence_agreement').is(':checked')) {
    $('#thesis_etd_licence_agreement').prop('disabled', true);
  }
  
  $('#yorkspace-licence').on('scroll', function() {
    var $this = $(this);
    if ($this.scrollTop() + $this.innerHeight() >= $this[0].scrollHeight) {
      $('#thesis_yorkspace_licence_agreement').prop('disabled', false);
    }
  });

  $('#etd-licence').on('scroll', function() {
    var $this = $(this);
    if ($this.scrollTop() + $this.innerHeight() >= $this[0].scrollHeight) {
      $('#thesis_etd_licence_agreement').prop('disabled', false);
    }
  });
});