// This is a manifest file that'll be compiled into application.js, which will include all the files
// listed below.
//
// Any JavaScript/Coffee file within this directory, lib/assets/javascripts, vendor/assets/javascripts,
// or vendor/assets/javascripts of plugins, if any, can be referenced here using a relative path.
//
// It's not advisable to add code directly here, but if you do, it'll appear at the bottom of the
// the compiled file.
//
// WARNING: THE FIRST BLANK LINE MARKS THE END OF WHAT'S TO BE PROCESSED, ANY BLANK LINE SHOULD
// GO AFTER THE REQUIRES BELOW.
//
//= require jquery3
//= require popper
//= require bootstrap-sprockets
//= require jquery
//= require jquery_ujs
//= require jquery-ui
//= require jquery-tablesorter
//= require chosen-jquery
//= require trix
//= require_self
//= require_tree .


$(document).ready(function () {
	$('.dropdown-toggle').dropdown();

	// disable in browser form validations
	$('form').find('input').removeAttr('required');

	$('.theses .options a').click(function (e) {
		e.preventDefault();
		$(this).tab('show');
		$(".theses .options a").removeClass("active")
		$(this).addClass("active")
	})
});

$(document).on('click', '#file_upload_button', function(e) {
	file = $(this).parents('form:first').find('input:file');
    if (file.val()) {
        var allowed = file.data('ext').split(',');
        var ext = '.' + file.val().split('.').pop().toLowerCase();
        if($.inArray(ext, allowed) == -1) {
            console.log('File extension ' + ext + ' is not allowed.');
        } else {
            return true;
        }
    } else {
    	alert('Please choose a file to upload.');
    }
    e.preventDefault();
    return false;
});