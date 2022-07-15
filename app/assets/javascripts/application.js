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
//= require jquery
//= require jquery_ujs
//= require jquery-ui
//= require jquery-tablesorter
//= require chosen-jquery
//= require_self
//= require_tree .


$(document).ready(function () {
	//$("input[placeholder], textarea[placeholder]").enablePlaceholder({"withPlaceholderClass": "light-text"});

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
