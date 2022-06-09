$(document).ready(function(){
	/* FORM */
	//$('#select_subjects_1, #select_subjects_2, #select_subjects_3').chosen({ max_selected_options: 1, allow_single_deselect: true });
	$('.select_subjects_fields').chosen({ max_selected_options: 1, allow_single_deselect: true });
	
  $('#thesis_exam_date').datepicker({ dateFormat: 'yy-mm-dd' });
	
	/** STATUS NOTIFICATIONS **/
  $("#status_change_link").popover( { 
		title: "Change Thesis Status", 
		placement: "bottom",
		html: true,
		content: $("#status_change").html(),
		trigger: "click"
		
	});
	
	
	/* ReadOnly Field View */
	$(".readonly-field a").click(function() {
		$(this).parent().hide();
		var show_field = $(this).data("id");
		$("#" + show_field).show();
		return false;
	});
	
	
	$(".simple_form").on("click", ".remove_fields", function(event) {
		$(this).prev("input[type=hidden]").val("1");
		$(this).closest("fieldset").hide();
		event.preventDefault();
	});

	$(".simple_form").on("click", ".add_fields", function(event) {
		var time = new Date().getTime();
		var regexp = new RegExp($(this).data("id"), "g");
		$(this).before($(this).data('fields').replace(regexp,time));
		event.preventDefault();
		
		$( ".committee_member_names" ).autocomplete({
		 source: committee_member_names_list
		});	
	});
	
	
});
